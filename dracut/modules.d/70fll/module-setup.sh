#!/bin/bash

check() {
    # live environment only
    [[ $hostonly ]] && return 1
    return 255
}

depends() {
    echo initqueue
    return 0
}

installkernel() {
    hostonly='' instmods iso9660 erofs loop squashfs \
        ext4 btrfs jfs f2fs xfs ntfs vfat exfat udf
}

install() {
    inst_multiple awk blkid blockdev cat dd echo grep losetup \
        mkdir mount readlink rmdir sed stat umount \
        fll_blockdev_detect
    inst_simple /etc/default/distro
    inst_hook mount 00 "$moddir/fll.sh"
    inst_script "$moddir/fll-udev.sh" "/sbin/fll-udev"
    inst_script "/usr/share/fll-live-initramfs/fll.initramfs" "/sbin/fll-live-root"
}
