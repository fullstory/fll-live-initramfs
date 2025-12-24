#!/bin/sh

PATH=/usr/sbin:/usr/bin:/sbin:/bin

init_debug_log()
{
    grep -qw fll=debug /proc/cmdline || return 0
    exec 6>&1
    exec 7>&2
    exec > debug.log
    exec 2>&1
    tail -f debug.log >&7 &
    echo "${!}" > debug.log.pid
    set -x
}

stop_debug_log()
{
    [ -f debug.log.pid ] || return 0
    set +x
    exec 1>&6 6>&-
    exec 2>&7 7>&-
    kill "$(cat debug.log.pid)"
    if [ -d "${NEWROOT}/var/log" ]; then
        mkdir -p "${NEWROOT}/var/log/fll"
        cp debug.log "${NEWROOT}/var/log/fll"
    fi
}

unset FLL_RC
init_debug_log
if fll_blockdev_detect --monitor --execp=/sbin/fll; then
    FLL_RC="${?}"
    ln -s null /dev/root
    : > /run/initramfs/.need_shutdown
fi
stop_debug_log
exit "${FLL_RC:-1}"
