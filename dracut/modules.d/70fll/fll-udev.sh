#!/bin/sh

PATH=/usr/sbin:/usr/bin:/sbin:/bin

fll_blockdev_detect --monitor --execp=/sbin/fll-live-root

exit $?
