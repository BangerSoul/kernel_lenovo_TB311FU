### AnyKernel3 Script for Lenovo Tab M11 (TB311FU / poplar / MT6769)
# PoplarKernel v1.1 by BangerSoul
# Built with KernelSU-Next, Built-in Wi-Fi & Full Android 15 GSI Compatibility

### Properties
properties() { '
kernel.string=PoplarKernel v1.1 with KernelSU-Next for Lenovo Tab M11 (TB311FU) by BangerSoul
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

ui_print " ";
ui_print "==========================================";
ui_print "       PoplarKernel v1.1 for Tab M11      ";
ui_print "           Developer: BangerSoul          ";
ui_print "        KernelSU-Next | Linux 6.6         ";
ui_print "     Built-in Wi-Fi (CFG80211 & RFKILL)   ";
ui_print "==========================================";
ui_print " ";

### GKI / Boot Header v4 Configuration
split_boot;

# Repack kernel image
flash_boot;

ui_print " ";
ui_print "  PoplarKernel v1.1 installed successfully! ";
ui_print "==========================================";
