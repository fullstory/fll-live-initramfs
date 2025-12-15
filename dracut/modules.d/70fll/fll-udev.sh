#!/bin/sh

PATH=/usr/sbin:/usr/bin:/sbin:/bin

if fll_blockdev_detect --monitor --execp=/sbin/fll-live-root; then
    ln -s null /dev/root
    : > /run/initramfs/.need_shutdown
    exit 0
fi

exit 1
