#!/bin/bash

check() {
    # live environment only
    [[ $hostonly ]] && return 1
    return 255
}

depends() {
    echo base fs-lib
}

installkernel() {
    hostonly='' instmods iso9660 erofs loop squashfs overlay \
        ext4 btrfs jfs f2fs xfs ntfs3 vfat exfat udf \
        of_pmem nd_pmem nfit
}

install() {
    inst_multiple awk blkid blockdev cat dd echo eject grep \
        losetup mkdir mount readlink rmdir sed stat umount \
        fll_blockdev_detect systemd-detect-virt
    inst_simple /etc/default/distro
    inst_hook mount 99 "$moddir/fll.sh"
    inst_script "/usr/share/fll-live-initramfs/fll.initramfs" "/sbin/fll"
    inst_script "/usr/share/fll-live-initramfs/fll.shutdown" \
        "/usr/lib/systemd/system-shutdown/fll"
}
