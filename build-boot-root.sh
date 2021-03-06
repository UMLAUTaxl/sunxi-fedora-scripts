#!/bin/sh
#
# This scripts builds Allwinner sunxi kernels + per board u-boot, spl and fex
# It will then place all the build files into 2 directories:
# $DESTDIR/uboot and $DESTDIR/rootfs
# and then tars up these directories to:
# $DESTDIR/uboot.tar.gz and $DESTDIR/rootfs.tar.gz
# Note that it also leaves the directories in place for easy inspection
#
# These tarbals are intended to be untarred to respectively the uboot and
# rootfs partition of a Fedora panda sdcard image, thereby turning this image
# into an Fedora sunxi sdcard image. See build-image.sh for a script automating
# this.
#
# The latest version of this script can be found here:
# https://github.com/jwrdegoede/sunxi-fedora-scripts.git
#
# To get the exact same versions as used on your sdcard, use the copy of
# this script found on your sdcard, as that contains all the git-tags used
# to build the sdcard image.
#
# This script must be run under Fedora-18 x86_64, with the following
# packages installed:
# gcc-arm-linux-gnu
# uboot-tools
#
# Also the fex2bin utility from:
# https://github.com/linux-sunxi/sunxi-tools.git
# (not yet packaged) needs to be available in the PATH somewhere
#
# This script must be run from a directory which contains clones of the
# following git repositories:
# https://github.com/jwrdegoede/sunxi-fedora-scripts.git
# https://github.com/jwrdegoede/u-boot-sunxi.git
# https://github.com/jwrdegoede/sunxi-boards.git
# https://github.com/jwrdegoede/sunxi-kernel-config.git
# https://github.com/jwrdegoede/linux-sunxi.git

KERNER_VER=3.4
A10_BOARDS="a10_mid_1gb ba10_tv_box coby_mid7042 coby_mid8042 coby_mid9742 cubieboard cubieboard_512 gooseberry_a721 h6 hackberry hyundai_a7hd inet97f-ii mele_a1000 mele_a1000g mini-x mini-x-1gb mk802 mk802-1gb mk802ii pov_protab2_ips9 pov_protab2_ips_3g uhost_u1a"
A13_BOARDS="a13_mid a13_olinuxino a13_olinuxino_micro"
UBOOT_TAG=fedora-18-16022013
KERNEL_CONFIG_TAG=fedora-18-16022013
KERNEL_TAG=fedora-18-16022013-2
SUNXI_BOARDS_TAG=fedora-18-16022013
SCRIPTS_TAG=fedora-18-16022013-2

for i in "$@"; do
    case $i in
        --noclean)
            NOCLEAN=1
            ;;
        --nocheckout)
            NOCHECKOUT=1
            ;;
        *)
            echo "Usage $0 [--noclean] [--nocheckout]"
            exit 1
    esac
done

if [ -z "$DESTDIR" ]; then
    DESTDIR=$(pwd)
fi

set -e
set -x

[ -d $DESTDIR/uboot ] && rm -r $DESTDIR/uboot
[ -d $DESTDIR/rootfs ] && rm -r $DESTDIR/rootfs
mkdir $DESTDIR/uboot
mkdir $DESTDIR/rootfs

pushd u-boot-sunxi
[ -z "$NOCHECKOUT" ] && git checkout $UBOOT_TAG
[ -z "$NOCLEAN" ] && git clean -dxf
mkdir $DESTDIR/uboot/boards
# Note the changing board configs always force a rebuild
mkdir $DESTDIR/uboot/boards/sun4i
for i in $A10_BOARDS; do
    make -j4 CROSS_COMPILE=arm-linux-gnu- O=$i distclean
    make -j4 CROSS_COMPILE=arm-linux-gnu- O=$i $i
    mkdir $DESTDIR/uboot/boards/sun4i/$i
    cp $i/spl/sunxi-spl.bin $DESTDIR/uboot/boards/sun4i/$i
    cp $i/u-boot.bin $DESTDIR/uboot/boards/sun4i/$i
done
mkdir $DESTDIR/uboot/boards/sun5i
for i in $A13_BOARDS; do
    make -j4 CROSS_COMPILE=arm-linux-gnu- O=$i distclean
    make -j4 CROSS_COMPILE=arm-linux-gnu- O=$i $i
    mkdir $DESTDIR/uboot/boards/sun5i/$i
    cp $i/spl/sunxi-spl.bin $DESTDIR/uboot/boards/sun5i/$i
    cp $i/u-boot.bin $DESTDIR/uboot/boards/sun5i/$i
done
popd

pushd sunxi-boards
[ -z "$NOCHECKOUT" ] && git checkout $SUNXI_BOARDS_TAG
[ -z "$NOCLEAN" ] && git clean -dxf
for i in $A10_BOARDS; do
    cp -p sys_config/a10/$i.fex $DESTDIR/uboot/boards/sun4i/$i
    fex2bin sys_config/a10/$i.fex $DESTDIR/uboot/boards/sun4i/$i/script.bin
done
for i in $A13_BOARDS; do
    cp -p sys_config/a13/$i.fex $DESTDIR/uboot/boards/sun5i/$i
    fex2bin sys_config/a13/$i.fex $DESTDIR/uboot/boards/sun5i/$i/script.bin
done
popd

pushd sunxi-kernel-config
[ -z "$NOCHECKOUT" ] && git checkout $KERNEL_CONFIG_TAG
[ -z "$NOCLEAN" ] && git clean -dxf
make VERSION=$KERNER_VER -f Makefile.config kernel-$KERNER_VER-armv7hl-sun4i.config
make VERSION=$KERNER_VER -f Makefile.config kernel-$KERNER_VER-armv7hl-sun5i.config
popd

pushd linux-sunxi
[ -z "$NOCHECKOUT" ] && git checkout $KERNEL_TAG
[ -z "$NOCLEAN" ] && git clean -dxf
mkdir -p sun4i sun5i
cp ../sunxi-kernel-config/kernel-$KERNER_VER-armv7hl-sun4i.config sun4i/.config
cp ../sunxi-kernel-config/kernel-$KERNER_VER-armv7hl-sun5i.config sun5i/.config
make O=sun4i ARCH=arm CROSS_COMPILE=arm-linux-gnu- CONFIG_DEBUG_SECTION_MISMATCH=y -j4 uImage modules
make O=sun5i ARCH=arm CROSS_COMPILE=arm-linux-gnu- CONFIG_DEBUG_SECTION_MISMATCH=y -j4 uImage modules

cp sun4i/arch/arm/boot/uImage $DESTDIR/uboot/uImage.sun4i
cp sun5i/arch/arm/boot/uImage $DESTDIR/uboot/uImage.sun5i

mkdir $DESTDIR/rootfs/usr
make O=sun4i ARCH=arm CROSS_COMPILE=arm-linux-gnu- INSTALL_MOD_PATH=$DESTDIR/rootfs/usr modules_install
make O=sun5i ARCH=arm CROSS_COMPILE=arm-linux-gnu- INSTALL_MOD_PATH=$DESTDIR/rootfs/usr modules_install
find $DESTDIR/rootfs/usr/lib/modules -name "*.ko" -exec arm-linux-gnu-strip --strip-debug '{}' \;

mkdir $DESTDIR/uboot/scripts
cp sun4i/.config $DESTDIR/uboot/scripts/kernel-$KERNER_VER-armv7hl-sun4i.config
cp sun5i/.config $DESTDIR/uboot/scripts/kernel-$KERNER_VER-armv7hl-sun5i.config
popd

pushd sunxi-fedora-scripts
[ -z "$NOCHECKOUT" ] && git checkout $SCRIPTS_TAG
[ -z "$NOCLEAN" ] && git clean -dxf
../u-boot-sunxi/mele_a1000/tools/mkenvimage -s 131072 \
  -o $DESTDIR/uboot/boards/uEnv-img.bin uEnv-full.txt
mkimage -C none -A arm -T script -d boot.cmd $DESTDIR/uboot/boot.scr
cp -p boot.cmd README select-board.sh $DESTDIR/uboot
cp -p uEnv-boot.txt $DESTDIR/uboot/uEnv.txt
cp -p build-boot-root.sh build-image.sh $DESTDIR/uboot/scripts
# replace rootfs-resize with one which understands running without an initrd
mkdir $DESTDIR/rootfs/usr/sbin
cp -p rootfs-resize $DESTDIR/rootfs/usr/sbin
popd

echo
echo "Successfully build uboot and rootfs directories, packing ..."

pushd $DESTDIR/uboot
tar cfz $DESTDIR/uboot.tar.gz *
popd

pushd $DESTDIR/rootfs
tar cfz $DESTDIR/rootfs.tar.gz *
popd

echo "Successfully generated uboot.tar.gz and rootfs.tar.gz"
