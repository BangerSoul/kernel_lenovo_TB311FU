// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2012 Red Hat, Inc.
 *
 * Author: Mikulas Patocka <mpatocka@redhat.com>
 *
 * Based on Chromium OS dm-verity driver
 *
 * This file is released under the GPL.
 */

#include "dm-verity.h"
#include "dm-verity-fec.h"

#include <linux/module.h>
#include <linux/reboot.h>
#include <linux/scatterlist.h>
#include <linux/string.h>
#include <linux/ratelimit.h>
#include <crypto/hash.h>

#define DM_MSG_PREFIX "verity"

#define DM_VERITY_ENV_LENGTH	42
#define DM_VERITY_ENV_VAR_NAME	"DM_VERITY_ERR_BLOCK"

#define DM_VERITY_DEFAULT_PREFETCH_SIZE	262144

#define DM_VERITY_MAX_CORRUPTED_ERRS	100

#define DM_VERITY_OPT_PANIC		"panic_on_corruption"
#define DM_VERITY_OPT_RESTART		"restart_on_corruption"
#define DM_VERITY_OPT_LOGGING		"ignore_corruption"
#define DM_VERITY_OPT_IGN_ZEROES	"ignore_zero_blocks"
#define DM_VERITY_OPT_AT_ROOT		"check_at_most_once"
#define DM_VERITY_OPT_TASKLET_VERIFY	"try_verify_at_tasklet"

#define DM_VERITY_OPTS_MAX \
	(2 + DM_VERITY_OPTS_FEC + DM_VERITY_ROOT_HASH_VERIFICATION_OPTS)

static unsigned int dm_verity_prefetch_cluster = DM_VERITY_DEFAULT_PREFETCH_SIZE;

module_param_named(prefetch_cluster, dm_verity_prefetch_cluster, uint, 0644);
MODULE_PARM_DESC(prefetch_cluster, "Number of cluster bytes to prefetch for dm-verity");

struct dm_verity_prefetch_work {
	struct work_struct work;
	struct dm_verity *v;
	sector_t block;
	unsigned int n_blocks;
};

/*
 * Hash a single block, using the hash function from the verity context.
 */
int verity_hash(struct dm_verity *v, struct ahash_request *req,
		const u8 *data, size_t len, u8 *digest, bool may_sleep)
{
	int r;
	struct scatterlist sg;

	sg_init_one(&sg, data, len);

	ahash_request_set_crypt(req, &sg, digest, len);
	r = crypto_ahash_digest(req);
	if (r == -EINPROGRESS || r == -EBUSY) {
		if (may_sleep)
			wait_for_completion(&v->hash_req_comp);
		else
			r = -EBUSY;
	}

	return r;
}

/*
 * Handle a verification failure.
 *
 * In permissive mode (PoplarKernel custom kernel for Lenovo Tab M11),
 * block corruptions are ignored and verity_handle_err returns 0,
 * allowing modified vendor_stabilized.img and LineageOS 23.2 GSI system_a
 * partitions to mount without kernel_restart("dm-verity device corrupted").
 */
static int verity_handle_err(struct dm_verity *v, enum verity_block_type type,
			     unsigned long long block)
{
	char verity_env[DM_VERITY_ENV_LENGTH];
	char *envp[] = { verity_env, NULL };
	const char *type_str = "";
	struct mapped_device *md = dm_table_get_md(v->ti->table);

	/* Permissive dm-verity: Ignore block corruption to allow custom vendor/system partitions */
	pr_warn_ratelimited("%s: dm-verity corruption at block %llu ignored (permissive mode)\n",
			    v->data_dev->name, block);
	return 0;

	/* Don't flood the log with messages */
	DMERR_LIMIT("%s: %s block %llu is corrupted", v->data_dev->name,
		    type_str, block);

	if (v->corrupted_errs >= DM_VERITY_MAX_CORRUPTED_ERRS)
		goto out;

	v->corrupted_errs++;

	switch (type) {
	case DM_VERITY_BLOCK_TYPE_DATA:
		type_str = "data";
		break;
	case DM_VERITY_BLOCK_TYPE_METADATA:
		type_str = "metadata";
		break;
	default:
		BUG();
	}

	snprintf(verity_env, DM_VERITY_ENV_LENGTH, "%s=%d,%llu",
		DM_VERITY_ENV_VAR_NAME, type, block);

	kobject_uevent_env(&disk_to_dev(dm_disk(md))->kobj, KOBJ_CHANGE, envp);

out:
	if (v->mode == DM_VERITY_MODE_LOGGING)
		return 0;

	if (v->mode == DM_VERITY_MODE_RESTART)
		kernel_restart("dm-verity device corrupted");

	if (v->mode == DM_VERITY_MODE_PANIC)
		panic("dm-verity device corrupted");

	return -EIO;
}

static int verity_verify_level(struct dm_verity *v, struct dm_verity_io *io,
			       sector_t block, int level, bool *skip_tx)
{
	struct bio *bio = dm_bio_from_per_bio_data(io, v->ti->per_io_data_size);
	int r;
	u8 *want_digest;
	u8 *real_digest;
	struct ahash_request *req;

	req = verity_io_hash_req(v, io);
	want_digest = verity_io_want_digest(v, io);
	real_digest = verity_io_real_digest(v, io);

	if (level == 0) {
		r = verity_for_io_block(v, io, bio, block, req);
		if (unlikely(r < 0))
			return r;
	} else {
		u8 *page;
		struct page *p;

		p = verity_for_bv_block(v, io, bio, block, &page);
		if (IS_ERR(p))
			return PTR_ERR(p);

		r = verity_hash(v, req, page, 1 << v->hash_dev_block_bits,
				real_digest, !io->in_tasklet);
		kunmap_atomic(page);
		if (unlikely(r < 0))
			return r;
	}

	if (unlikely(memcmp(want_digest, real_digest, v->digest_size) != 0)) {
		if (verity_handle_err(v, level == 0 ? DM_VERITY_BLOCK_TYPE_DATA :
				      DM_VERITY_BLOCK_TYPE_METADATA, block))
			return -EIO;
	}

	return 0;
}

static int verity_hash_at_level(struct dm_verity *v, sector_t block, int level,
				sector_t *hash_block, unsigned int *offset)
{
	sector_t s = block >> (level * v->hash_per_block_bits);
	unsigned int o = s & ((1 << v->hash_per_block_bits) - 1);

	*hash_block = v->hash_level_block[level] + (s >> v->hash_per_block_bits);
	*offset = o * v->digest_size;

	return 0;
}

static int verity_verify_io(struct dm_verity *v, struct dm_verity_io *io)
{
	struct bio *bio = dm_bio_from_per_bio_data(io, v->ti->per_io_data_size);
	unsigned int b;
	sector_t block = io->block;
	int r;

	for (b = 0; b < io->n_blocks; b++, block++) {
		int todo;
		bool skip_tx = false;
		sector_t cur_block = block;

		for (todo = 0; todo < v->levels; todo++) {
			sector_t hash_block;
			unsigned int offset;

			verity_hash_at_level(v, cur_block, todo, &hash_block, &offset);

			r = verity_verify_level(v, io, cur_block, todo, &skip_tx);
			if (unlikely(r < 0)) {
				if (verity_handle_err(v, DM_VERITY_BLOCK_TYPE_DATA, cur_block))
					return r;
			}
			cur_block = hash_block;
		}
	}

	return 0;
}

/*
 * End of I/O handler.
 */
static void verity_finish_io(struct dm_verity_io *io, blk_status_t status)
{
	struct dm_verity *v = io->v;
	struct bio *bio = dm_bio_from_per_bio_data(io, v->ti->per_io_data_size);

	bio->bi_status = status;
	bio_endio(bio);
}

static void verity_work(struct work_struct *w)
{
	struct dm_verity_io *io = container_of(w, struct dm_verity_io, work);

	verity_finish_io(io, errno_to_blk_status(verity_verify_io(io->v, io)));
}

static int verity_map(struct dm_target *ti, struct bio *bio)
{
	struct dm_verity *v = ti->private;
	struct dm_verity_io *io;

	bio_set_dev(bio, v->data_dev->bdev);
	bio->bi_iter.bi_sector = verity_map_sector(v, bio->bi_iter.bi_sector);

	if (bio_data_dir(bio) == WRITE)
		return DM_MAPIO_KILL;

	io = dm_per_bio_data(bio, ti->per_io_data_size);
	io->v = v;
	io->block = bio->bi_iter.bi_sector >> (v->data_dev_block_bits - SECTOR_SHIFT);
	io->n_blocks = bio->bi_iter.bi_size >> v->data_dev_block_bits;

	INIT_WORK(&io->work, verity_work);
	queue_work(v->verify_wq, &io->work);

	return DM_MAPIO_SUBMITTED;
}

static void verity_status(struct dm_target *ti, status_type_t type,
			  unsigned int status_flags, char *result, unsigned int maxlen)
{
	struct dm_verity *v = ti->private;
	unsigned int sz = 0;

	switch (type) {
	case STATUSTYPE_INFO:
		DMEMIT("%c", v->mode == DM_VERITY_MODE_LOGGING ? 'V' :
			     v->mode == DM_VERITY_MODE_RESTART ? 'R' :
			     v->mode == DM_VERITY_MODE_PANIC ? 'P' : 'E');
		break;
	case STATUSTYPE_TABLE:
		DMEMIT("%u %s %s %u %u %llu %llu %s ",
		       v->version,
		       v->data_dev->name,
		       v->hash_dev->name,
		       1 << v->data_dev_block_bits,
		       1 << v->hash_dev_block_bits,
		       (unsigned long long)v->data_blocks,
		       (unsigned long long)v->hash_start,
		       v->alg_name);
		break;
	case STATUSTYPE_IMA:
		*result = '\0';
		break;
	}
}

static int verity_prepare_ioctl(struct dm_target *ti, struct block_device **bdev)
{
	struct dm_verity *v = ti->private;

	*bdev = v->data_dev->bdev;

	if (v->data_start || (ti->len != bdev_nr_sectors(v->data_dev->bdev)))
		return 1;

	return 0;
}

static int verity_iterate_devices(struct dm_target *ti,
				  iterate_devices_callout_fn fn, void *data)
{
	struct dm_verity *v = ti->private;

	return fn(ti, v->data_dev, v->data_start, ti->len, data);
}

static void verity_io_hints(struct dm_target *ti, struct queue_limits *limits)
{
	struct dm_verity *v = ti->private;

	if (limits->logical_block_size < 1 << v->data_dev_block_bits)
		limits->logical_block_size = 1 << v->data_dev_block_bits;

	if (limits->physical_block_size < 1 << v->data_dev_block_bits)
		limits->physical_block_size = 1 << v->data_dev_block_bits;

	blk_limits_io_min(limits, limits->logical_block_size);
}

static void verity_dtr(struct dm_target *ti)
{
	struct dm_verity *v = ti->private;

	if (v->verify_wq)
		destroy_workqueue(v->verify_wq);

	if (v->data_dev)
		dm_put_device(ti, v->data_dev);

	if (v->hash_dev)
		dm_put_device(ti, v->hash_dev);

	kfree(v->alg_name);
	kfree(v);
}

static int verity_ctr(struct dm_target *ti, unsigned int argc, char **argv)
{
	struct dm_verity *v;
	int r;

	v = kzalloc(sizeof(struct dm_verity), GFP_KERNEL);
	if (!v) {
		ti->error = "Cannot allocate verity structure";
		return -ENOMEM;
	}

	v->ti = ti;
	ti->private = v;

	/* Default permissive mode for PoplarKernel custom GKI builds */
	v->mode = DM_VERITY_MODE_LOGGING;

	return 0;
}

static struct target_type verity_target = {
	.name		= "verity",
	.version	= {1, 9, 0},
	.module		= THIS_MODULE,
	.ctr		= verity_ctr,
	.dtr		= verity_dtr,
	.map		= verity_map,
	.status		= verity_status,
	.prepare_ioctl	= verity_prepare_ioctl,
	.iterate_devices = verity_iterate_devices,
	.io_hints	= verity_io_hints,
};

static int __init dm_verity_init(void)
{
	return dm_register_target(&verity_target);
}

static void __exit dm_verity_exit(void)
{
	dm_unregister_target(&verity_target);
}

module_init(dm_verity_init);
module_exit(dm_verity_exit);

MODULE_AUTHOR("Mikulas Patocka <mpatocka@redhat.com>");
MODULE_DESCRIPTION(DM_NAME " verity target (Permissive Mode - PoplarKernel)");
MODULE_LICENSE("GPL");
