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
# begin properties
. /tmp/anykernel/tools/ak3-core.sh;

### GKI / Boot Header v4 Configuration
split_boot;

# Repack kernel image
flash_boot;

# Repack DTBO partition if present
flash_dtbo;
