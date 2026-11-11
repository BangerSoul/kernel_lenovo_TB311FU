### AnyKernel3 Script for Lenovo Tab M11 (TB311FU / MT6769)
# osm0sis @ xda-developers

### Properties
properties() { '
kernel.string=Custom Kernel with KernelSU-Next for Lenovo Tab M11 (TB311FU)
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=TB311FU
device.name2=poplar
device.name3=tb8786p1_64_k66
device.name4=MT6769
device.name5=mt6768
supported.versions=12, 12.1, 13, 14, 15
supported.patchlevels=
'; }

### AnyKernel setup
# Both uppercase and lowercase for maximum compatibility
block=boot;
BLOCK=boot;
is_slot_device=auto;
IS_SLOT_DEVICE=auto;
ramdisk_compression=auto;
RAMDISK_COMPRESSION=auto;

# import functions/variables and setup environment
if [ -f "$AKHOME/tools/ak3-core.sh" ]; then
  . "$AKHOME/tools/ak3-core.sh";
elif [ -f "./tools/ak3-core.sh" ]; then
  . ./tools/ak3-core.sh;
elif [ -f "/tmp/anykernel/tools/ak3-core.sh" ]; then
  . /tmp/anykernel/tools/ak3-core.sh;
fi;

### GKI / Boot Header v4 Configuration
split_boot;

# Repack kernel image
flash_boot;
