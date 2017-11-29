#!/bin/sh

set -e

# TODO - this shell script file needs serios refactoring since right now it does
# too many things:
#
# 1) Create proper overlay structure.
# 2) Prepare the actual ISO structure.
# 3) Generate the actual ISO image.
#
# Probably it's best to create separate shell scripts for each functionality.

echo "*** GENERATE ISO BEGIN ***"

SRC_DIR=$(pwd)

# Save the kernel installation directory.
KERNEL_INSTALLED=$SRC_DIR/work/kernel/kernel_installed

# Find the Syslinux build directory.
cd work/syslinux
cd $(ls -d *)
WORK_SYSLINUX_DIR=$(pwd)
cd $SRC_DIR

# Remove the old ISO file if it exists.
rm -f minimal_linux_live.iso
echo "Old ISO image file has been removed."

# Remove the old ISO generation area if it exists.
echo "Removing old ISO image work area. This may take a while..."
rm -rf work/isoimage

# This is the root folder of the ISO image.
mkdir work/isoimage
echo "Prepared new ISO image work area."

# Read the 'COPY_SOURCE_ISO' property from '.config'
COPY_SOURCE_ISO="$(grep -i ^COPY_SOURCE_ISO .config | cut -f2 -d'=')"

cd work/isoimage

# Now we copy the kernel.
cp $KERNEL_INSTALLED/kernel ./kernel.xz

# Now we copy the root file system.
cp ../rootfs.cpio.xz ./rootfs.xz

# Read the 'OVERLAY_TYPE' property from '.config'
OVERLAY_TYPE="$(grep -i ^OVERLAY_TYPE $SRC_DIR/.config | cut -f2 -d'=')"

# Read the 'OVERLAY_LOCATION' property from '.config'
OVERLAY_LOCATION="$(grep -i ^OVERLAY_LOCATION $SRC_DIR/.config | cut -f2 -d'=')"

if [ "$OVERLAY_LOCATION" = "iso" \
  -a "$OVERLAY_TYPE" = "sparse" \
  -a -d $SRC_DIR/work/overlay_rootfs \
  -a "$(id -u)" = "0" ] ; then

  # Use sparse file as storage place. The above check guarantees that the whole
  # script is executed with root permissions or otherwise this block is skipped.
  # All files and folders located in the folder 'minimal_overlay' will be merged
  # with the root folder on boot.

  echo "Using sparse file for overlay."

  # This is the BusyBox executable that we have already generated.
  BUSYBOX=../rootfs/bin/busybox

  # Create sparse image file with 1MB size. Note that this increases the ISO
  # image size.
  $BUSYBOX truncate -s 1M minimal.img

  # Find available loop device.
  LOOP_DEVICE=$($BUSYBOX losetup -f)

  # Associate the available loop device with the sparse image file.
  $BUSYBOX losetup $LOOP_DEVICE minimal.img

  # Format the sparse image file with Ext2 file system.
  $BUSYBOX mkfs.ext2 $LOOP_DEVICE

  # Mount the sparse file in folder 'sparse".
  mkdir sparse
  $BUSYBOX mount minimal.img sparse

  # Create the overlay folders.
  mkdir -p sparse/rootfs
  mkdir -p sparse/work

  # Copy the overlay content.
  cp -r $SRC_DIR/overlay_rootfs/* sparse/rootfs
  cp -r $SRC_DIR/minimal_overlay/rootfs/* sparse/rootfs

  # Unmount the sparse file and delete the temporary folder.
  $BUSYBOX umount sparse
  rm -rf sparse

  # Detach the loop device since we no longer need it.
  $BUSYBOX losetup -d $LOOP_DEVICE
elif [ "$OVERLAY_LOCATION" = "iso" \
  -a "$OVERLAY_TYPE" = "folder" \
  -a -d $SRC_DIR/work/overlay_rootfs ] ; then

  # Use normal folder structure for overlay. All files and folders located in
  # the folder 'minimal_overlay' will be merged with the root folder on boot.

  echo "Using folder structure for overlay."

  # Create the overlay folders.
  mkdir -p minimal/rootfs
  mkdir -p minimal/work

  # Copy the overlay content.
  cp -rf $SRC_DIR/work/overlay_rootfs/* minimal/rootfs
  cp -r $SRC_DIR/minimal_overlay/rootfs/* minimal/rootfs
else
  echo "The ISO image will have no overlay structure."
fi

# Copy the precompiled files 'isolinux.bin' and 'ldlinux.c32' in the ISO image
# root folder.
cp $WORK_SYSLINUX_DIR/bios/core/isolinux.bin .
cp $WORK_SYSLINUX_DIR/bios/com32/elflink/ldlinux/ldlinux.c32 .

# Create the ISOLINUX configuration file.
echo 'default kernel.xz  initrd=rootfs.xz vga=ask' > ./syslinux.cfg

# Create UEFI start script.
mkdir -p efi/boot
cat << CEOF > ./efi/boot/startup.nsh
echo -off
echo Minimal Linux Live is starting...
\\kernel.xz initrd=\\rootfs.xz
CEOF

# Now we generate the ISO image file.
xorriso \
  -as mkisofs \
  -R \
  -r \
  -o ../minimal_linux_live.iso \
  -b isolinux.bin \
  -c boot.cat \
  -input-charset UTF-8 \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  ./

# Copy the ISO image to the root project folder.
cp ../minimal_linux_live.iso ../../

if [ "$(id -u)" = "0" ] ; then
  # Apply ownership back to original owner for all affected files.
  chown $(logname) ../../minimal_linux_live.iso
  chown $(logname) ../../work/minimal_linux_live.iso
  chown -R $(logname) .
  echo "Applied original ownership to all affected files and folders."
fi

cd $SRC_DIR

cat << CEOF

  #################################################################
  #                                                               #
  #  ISO image file 'minimal_linux_live.iso' has been generated.  #
  #                                                               #
  #################################################################

CEOF

echo "*** GENERATE ISO END ***"
