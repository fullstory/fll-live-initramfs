# fll-live-initramfs

Early userspace glue for booting [F.U.L.L.S.T.O.R.Y](https://github.com/fullstory)
live media. Supports both **dracut** and **initramfs-tools** as initramfs generators.

## Overview

This package installs two scripts plus the generator-specific infrastructure needed
to produce an initramfs that can boot live media:

| Script | Purpose |
|--------|---------|
| `fll.initramfs` | Mounts the read-only rootfs and sets up the overlay COW layer, persistence, hostname, timezone, and getty |
| `fll.shutdown` | Runs at shutdown via systemd-shutdown |

The scripts are generator-agnostic shell. The generator-specific layers (described
below) embed them into the initramfs and wire them into the correct hooks.

---

## fll.initramfs

`fll.initramfs` is called once per block device candidate by `fll_blockdev_detect`.
It receives the device path and filesystem type via the environment (`$DEVNAME`,
`$ID_FS_TYPE`, `$ID_FS_UUID`) and performs the following in order:

1. Parses boot parameters from `/proc/cmdline`.
2. Identifies the block device carrying the live media — either an iso9660/carrier
   filesystem (USB stick, optical disc) or a bare rootfs partition exposed by a
   hybrid GPT layout.
3. Optionally copies the rootfs image into a tmpfs (`toram`).
4. Mounts the read-only rootfs (erofs, squashfs, ext4, …).
5. Sets up the overlay — either a volatile tmpfs COW layer (non-persistent) or a
   btrfs `@root` subvolume (persistent, optionally LUKS-encrypted).
6. Bind-mounts the btrfs `@home` subvolume over `/home` when persisting.
7. Writes a udev rule (`/etc/udev/rules.d/70-fll-live.rules`) to create a
   persistent `/dev/fll` symlink (and `/dev/fll-cdrom` for optical drives).
8. Patches Calamares configuration (readonly fstype, initramfs tool, bootloader).
9. Configures hostname, timezone (`/etc/timezone`, `/etc/localtime`, `/etc/adjtime`),
   and the live getty (`getty@.service` override).

The script detects whether it is running under **dracut** (via `$NEWROOT`) or
**initramfs-tools** (via `$rootmnt`) and sets the root mount point accordingly.

---

## fll.shutdown

`fll.shutdown` is installed as a systemd-shutdown drop-in
(`/usr/lib/systemd/system-shutdown/fll`). When the system shuts down or reboots,
systemd pivots back into the initramfs and runs all scripts in that directory.

If `/dev/fll-cdrom` exists (i.e. the live media was optical and `noeject` was not
used, and the system is not a virtual machine), `fll.shutdown` calls `eject` and
waits for the user to remove the disc before continuing.

---

## Boot parameters (cheatcodes)

All parameters are read from the kernel command line (`/proc/cmdline`). Parameters
are of the form `key=value` or bare words.

### Media location

| Parameter | Example | Description |
|-----------|---------|-------------|
| `iso_uuid=UUID` | `iso_uuid=1234-ABCD` | UUID of the iso9660 carrier filesystem. Used to identify the correct block device when multiple removable devices are present. Typically set by the bootloader. |
| `rootfs_uuid=UUID` | `rootfs_uuid=abcd-1234` | UUID of the rootfs partition itself (e.g. an erofs partition exposed directly by a hybrid GPT image). When this is set the script skips the iso9660 container and mounts the partition directly. |
| `fromiso=PATH` | `fromiso=/live/image.iso` | Path to an ISO file on a filesystem. The file is loop-mounted as an iso9660 volume and the rootfs image is read from within it. |
| `fromhd=DEV` | `fromhd=UUID=1234-ABCD` | Restrict probing to a specific block device. Accepts `UUID=<uuid>`, `/dev/disk/by-uuid/<uuid>`, or a `/dev/*` path. Set automatically by **grub2-fll-fromiso**. |
| `image_dir=DIR` | `image_dir=live` | Override the directory inside the carrier filesystem that contains the rootfs image file. Defaults to the value from `/etc/default/distro`. |
| `image_file=FILE` | `image_file=filesystem.erofs` | Override the rootfs image filename. Defaults to the value from `/etc/default/distro`. |

### Persistence

| Parameter | Example | Description |
|-----------|---------|-------------|
| `persist_uuid=UUID` | `persist_uuid=dead-beef` | UUID of a btrfs partition to use for persistent storage. The `@root` subvolume is used as the overlay upper directory; `@home` is bind-mounted over `/home`. Both `persist_uuid` and `rootfs_uuid` must be given together. |
| `persist_luks_uuid=UUID` | `persist_luks_uuid=cafe-1234` | UUID of a LUKS container wrapping the persist btrfs partition. When set, the passphrase is requested via Plymouth (with up to 3 attempts) or read from `/dev/console`. The unlocked device appears as `/dev/mapper/fll-persist`. |

### Locale and identity

| Parameter | Example | Description |
|-----------|---------|-------------|
| `hostname=NAME` | `hostname=mymachine` | Set a custom hostname in `/etc/hostname`, `/etc/mailname`, and `/etc/hosts`. |
| `tz=TIMEZONE` | `tz=Europe/Berlin` | Set the timezone. Must match a path under `/usr/share/zoneinfo/`. Both `/etc/timezone` and `/etc/localtime` are written. If omitted, defaults to `Etc/UTC` and Calamares is configured to perform a GeoIP timezone lookup. |
| `utc=yes` | | Write `/etc/adjtime` with `UTC` mode (hardware clock is UTC). |
| `utc` or `gmt` | | Alias for `tz=Etc/UTC`. |
| `username=NAME` | `username=alice` | Override the live username written to `/etc/default/distro`. |

### Debugging

| Parameter | Description |
|-----------|-------------|
| `fll.debug` or `fll=debug` | Enable `set -x` shell tracing in `fll.initramfs` and the generator-specific wrapper script. The trace is written to `debug.log` in the initramfs working directory and copied to `/var/log/fll/debug.log` in the booted system if `/var/log` exists. The environment is also dumped at startup. |

---

## initramfs-tools support

Files installed under `initramfs-tools/` are placed by the package into
`/usr/share/initramfs-tools/`:

```
initramfs-tools/
├── hooks/fll      → /usr/share/initramfs-tools/hooks/fll
└── scripts/fll    → /usr/share/initramfs-tools/scripts/fll
```

**`hooks/fll`** runs at initramfs build time (`update-initramfs`). It copies the
required kernel modules (overlay, erofs, squashfs, dm-crypt, ntfs3, vfat, exfat,
loop, NLS modules, pmem modules for UEFI HTTP boot), binaries (`fll_blockdev_detect`,
`cryptsetup`, `eject`, `systemd-detect-virt`), and the two fll scripts into the
initramfs image. It also installs `/shutdown` (systemd-shutdown binary) and
`/etc/initrd-release` so that systemd recognises the initramfs as an initrd
environment.

**`scripts/fll`** provides the `mountroot()` function called by the initramfs-tools
init framework. It:

1. Runs `/scripts/local-top` (e.g. for LVM).
2. Calls `fll_blockdev_detect --monitor --execp=/usr/lib/fll/fll.initramfs` to
   listen for udev block device events and invoke `fll.initramfs` for each
   candidate until the live media is found.
3. Copies the running initramfs into `/run/initramfs/` (the systemd exitrd) and
   strips modules and firmware to conserve memory.

---

## dracut support

Files installed under `dracut/` are placed by the package into `/usr/lib/`:

```
dracut/
├── dracut.conf.d/fll/10-fll.conf   → /usr/lib/dracut/dracut.conf.d/fll/10-fll.conf
└── modules.d/70fll/
    ├── module-setup.sh              → /usr/lib/dracut/modules.d/70fll/module-setup.sh
    └── fll.sh                       → /usr/lib/dracut/modules.d/70fll/fll.sh
```

**`10-fll.conf`** sets dracut to non-hostonly mode (generic initramfs), includes
the `fll` module, and compresses the output with `zstd` at level 3.

**`module-setup.sh`** is the dracut module descriptor. Its functions:

- `check()` — refuses to install in hostonly mode (live-only module).
- `depends()` — declares dependencies on the `base` and `fs-lib` dracut modules.
- `installkernel()` — adds kernel modules: iso9660, erofs, loop, squashfs, overlay,
  common filesystems (ext4, btrfs, jfs, f2fs, xfs, ntfs3, vfat, exfat, udf),
  pmem modules (of_pmem, nd_pmem, nfit), and dm-crypt.
- `install()` — copies required userspace binaries and installs `fll.sh` as a
  mount-phase hook (priority 99), `fll.initramfs` as `/sbin/fll`, and `fll.shutdown`
  as `/usr/lib/systemd/system-shutdown/fll`.

**`fll.sh`** is the dracut mount hook. It calls
`fll_blockdev_detect --monitor --execp=/sbin/fll`, creates the `/dev/root` null
symlink required by dracut to signal that root has been found, and touches
`/run/initramfs/.need_shutdown` to activate the systemd exitrd path.

---

## Installed file layout

```
/usr/share/fll-live-initramfs/
├── fll.initramfs          # main live mount script (shared by both generators)
└── fll.shutdown           # systemd-shutdown eject script

/usr/share/initramfs-tools/
├── hooks/fll              # initramfs-tools build hook
└── scripts/fll            # initramfs-tools mountroot() implementation

/usr/lib/dracut/
├── dracut.conf.d/fll/10-fll.conf
└── modules.d/70fll/
    ├── module-setup.sh
    └── fll.sh
```

---

## License

GPLv2. See `debian/copyright` for the full list of copyright holders.
