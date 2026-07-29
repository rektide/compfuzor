#!/bin/bash
# identity.sh — (re)provision a Linux system/disk identity, for clone-ready images.
#
# Derived from pivot-bdr.srv.pb's clone-reset.sh (the in-repo origin of the
# machine-id "truncate-don't-delete" gotcha and the dbus-id/ssh-key clearing).
# This is the canonical, maintained version; clone-reset.sh is the ancestor.
# See pivot-bdr.srv.pb:230 for the original.
#
# WHY this exists: a cloned system shares machine-id, ssh host keys, entropy
# seed, and (for dd'd disks) every filesystem/partition UUID. Two clones on one
# kernel collide. mkosi images should ship BLANK and self-provision on first
# boot; this tool either marks them for that (--first-boot, default) or builds a
# fresh identity outright (--generate), including block UUIDs for cloned disks.
#
# USAGE
#   identity.sh [MODE] [IDENTITY OPTS] [BLOCK OPTS]
#
# MODE (mutually exclusive):
#   --first-boot   (default) Blank userspace identity so the next boot regenerates
#                  it via systemd-firstboot / ConditionFirstBoot. Non-destructive
#                  to block UUIDs. Mirrors + extends clone-reset.sh.
#   --generate     Generate fresh identity NOW (write a new machine-id, generate
#                  ssh host keys) instead of deferring. With --new, also regenerates
#                  block UUIDs on the target disk/partition.
#
# IDENTITY OPTS (userspace; applies to --first-boot and --generate):
#   --root DIR     Root tree to operate on (default: /). /etc/machine-id etc.
#                  For --generate, DIR must be writable/mounted.
#
# BLOCK OPTS (--generate only, for dd-cloned disks/images):
#   --new X        Target to re-identify: a whole disk (/dev/sda) OR a single
#                  partition (/dev/sda1). Default: disk backing --root.
#   --old X        Source disk the clone was made from. REQUIRED for block ops
#                  unless --force-disks. Used as a guard: we refuse if --new and
#                  --old resolve to the same device (you'd be re-keying the original).
#   --force-disks  Skip the --old requirement and the same-device guard.
#   --force        Proceed even if --new filesystems are mounted (DANGEROUS:
#                  regenerating a UUID on a mounted fs corrupts the live mount).
#
# Partition/fs types handled: GPT (sgdisk) and DOS/MBR (no partuuid to change),
# ext2/3/4 (tune2fs), xfs (xfs_admin), btrfs (btrfstune), swap (swaplabel).
# After block regen, old->new UUIDs are rewritten in --root's /etc/fstab and
# /etc/kernel/cmdline so the clone still boots.
#
# Host deps: systemd (systemd-id128, systemd-firstboot), util-linux (blkid,
# findmnt, lsblk, swaplabel), gdisk, e2fsprogs, xfsprogs, btrfs-progs, openssh-server.

set -euo pipefail

die()  { printf 'identity: error: %s\n' "$*" >&2; exit 1; }
note() { printf 'identity: %s\n' "$*"; }

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-2}"; }

MODE=first-boot
ROOT=/
NEW=""
OLD=""
FORCE_DISKS=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --first-boot)  MODE=first-boot ;;
    --generate)    MODE=generate ;;
    --root)        ROOT="${2:?--root needs a DIR}"; shift ;;
    --new)         NEW="${2:?--new needs a DISK|PART}"; shift ;;
    --old)         OLD="${2:?--old needs a DISK}"; shift ;;
    --force-disks) FORCE_DISKS=1 ;;
    --force)       FORCE=1 ;;
    -h|--help)     usage 0 ;;
    *)             die "unknown arg: $1 (try --help)" ;;
  esac
  shift
done

# --- device helpers ---------------------------------------------------------
whole_disk_of() { lsblk -ndo PKNAME "$1" 2>/dev/null | sed 's/^/\/dev\//'; }
dev_type()       { lsblk -ndo TYPE "$1" 2>/dev/null; }
pttype()       { lsblk -ndo PTTYPE "$1" 2>/dev/null | head -1 || true; }
is_mounted()     { findmnt -nro SOURCE,MOUNTPOINT --source "$1" 2>/dev/null | grep -q . ; }

resolve_new() {
  # findmnt may return a btrfs subvol form like /dev/nvme0n1p6[/@root]; strip [/...].
  local src="${NEW:-$(findmnt -nro SOURCE "$ROOT" 2>/dev/null | sed 's/\[.*//' || true)}"
  [ -n "$src" ] || die "could not determine --new (no --root mount source); pass --new DISK|PART"
  [ -b "$src" ] || die "--new $src is not a block device"
  NEW="$src"
}

# --- userspace identity -----------------------------------------------------
do_first_boot() {
  local r="$ROOT"
  note "first-boot: blanking userspace identity under $r"
  : > "$r/etc/machine-id"                    # empty -> systemd regenerates (NOT delete; see header)
  rm -f "$r/var/lib/dbus/machine-id"         # dbus id (symlink on modern systems)
  rm -f "$r"/etc/ssh/ssh_host_*              # regenerate host keys on first sshd start
  rm -f "$r/var/lib/systemd/random-seed" "$r/var/lib/systemd/credential.secret" 2>/dev/null || true
  rm -rf "$r"/var/log/journal/* 2>/dev/null || true   # keyed on old machine-id; now stale
  rm -f "$r/etc/cloud/cloud-init.disabled" 2>/dev/null || true
  if [ "$r" = "/" ] && command -v systemd-firstboot >/dev/null 2>&1; then
    systemd-firstboot --reset || true        # arm ConditionFirstBoot units
  fi
  note "first-boot done; identity regenerates on next boot"
  note "verify after boot: systemd-id128 machine-id"
}

do_generate_userspace() {
  local r="$ROOT"
  note "generate: writing fresh userspace identity under $r"
  if ! systemd-id128 new >/dev/null 2>&1; then die "systemd-id128 unavailable"; fi
  install -m 444 <(systemd-id128 new) "$r/etc/machine-id"
  rm -f "$r/var/lib/dbus/machine-id"         # re-resolves to /etc/machine-id symlink
  if [ -d "$r/etc/ssh" ] && command -v ssh-keygen >/dev/null 2>&1; then
    ( cd "$r" && ssh-keygen -A 2>/dev/null ) || note "ssh-keygen -A skipped (no /etc/ssh?)"
  fi
  note "generate userspace done; machine-id: $(cat "$r/etc/machine-id")"
}

# --- block identity ---------------------------------------------------------
# Regen FS UUID of one partition node. Echoes "OLD NEW" for fstab rewrite.
regen_fs_uuid() {
  local part="$1" fstype old new
  fstype=$(blkid -s TYPE -o value "$part" 2>/dev/null || true)
  old=$(blkid -s UUID -o value "$part" 2>/dev/null || true)
  case "$fstype" in
    ext2|ext3|ext4) tune2fs -U random "$part" ;;
    xfs)            xfs_admin -U generate "$part" ;;
    btrfs)          btrfstune -u "$part" ;;
    swap)           swaplabel -U "$(systemd-id128 new -u)" "$part" ;;
    "")             note "  $part: no filesystem detected; skip" ; return 0 ;;
    *)              note "  $part: unsupported fs '$fstype'; skip" ; return 0 ;;
  esac
  new=$(blkid -s UUID -o value "$part" 2>/dev/null || true)
  [ -n "$old" ] && [ -n "$new" ] && printf '%s %s\n' "$old" "$new"
}

# Rewrite old->new UUID refs in fstab + kernel cmdline so the clone still boots.
rewrite_uuid_refs() {
  local root="$1"; shift
  local pair oldnew files=()
  [ -f "$root/etc/fstab" ] && files+=("$root/etc/fstab")
  [ -f "$root/etc/kernel/cmdline" ] && files+=("$root/etc/kernel/cmdline")
  [ ${#files[@]} -eq 0 ] && return 0
  for pair in "$@"; do
    set -- $pair; local o="$1" n="$2"
    for f in "${files[@]}"; do
      if grep -q "$o" "$f"; then sed -i "s/$o/$n/g" "$f"; note "  rewrote $o -> $n in ${f#$root}"; fi
    done
  done
}

do_block() {
  [ -n "$NEW" ] || return 0
  local disk parttype target_disk partno p pairs=()

  # guard: --old required unless --force-disks
  if [ "$FORCE_DISKS" -eq 0 ]; then
    [ -n "$OLD" ] || die "block ops need --old (the clone source) for safety, or --force-disks"
    [ -b "$OLD" ] || die "--old $OLD is not a block device"
    local new_disk old_disk
    new_disk=$(whole_disk_of "$NEW" || true); [ -n "$new_disk" ] || new_disk="$NEW"
    old_disk=$(whole_disk_of "$OLD" || true); [ -n "$old_disk" ] || old_disk="$OLD"
    if [ "$(readlink -f "$new_disk")" = "$(readlink -f "$old_disk")" ]; then
      die "--new ($new_disk) and --old ($old_disk) are the same device — refusing to re-key the source (use --force-disks)"
    fi
    note "guard ok: --new $new_disk differs from --old $old_disk"
  fi

  # mounted check
  if [ "$FORCE" -eq 0 ]; then
    local m
    for m in $(lsblk -nrpo NAME,MOUNTPOINT "$NEW" 2>/dev/null | awk '$2!=""{print $1}'); do
      die "$m is mounted; unmount before regenerating UUIDs (or --force, DANGEROUS)"
    done
  fi

  target_disk=$(whole_disk_of "$NEW" || true)
  if [ -n "$target_disk" ]; then
    # --new is a partition
    disk="$target_disk"; partno="${NEW##*[!0-9]}"
    note "block: single partition $NEW (on $disk)"
  else
    # --new is a whole disk
    disk="$NEW"
    note "block: whole disk $disk"
  fi

  parttype=$(pttype "$disk")
  case "$parttype" in
    gpt)
      note "  GPT: randomizing disk GUID + partition GUIDs ($disk)"
      if [ -n "$target_disk" ]; then
        sgdisk --partition-guid="${partno:-0}:R" "$disk" || die "sgdisk partition-guid failed"
      else
        sgdisk -G "$disk" || die "sgdisk -G failed (randomize all GUIDs)"
      fi ;;
    dos)
      note "  DOS/MBR: no partition UUIDs to change ($disk); skipping GPT step"
      note "    (this VPS is BIOS/MBR — partuuids don't apply, which is fine here)" ;;
    "")
      note "  no partition table on $disk; skipping GUID step" ;;
    *)
      note "  unhandled PTTYPE '$parttype'; skipping GUID step" ;;
  esac

  # FS UUID regen: the single partition if --new was one, else all partitions on the disk
  if [ -n "$target_disk" ]; then
    pair=$(regen_fs_uuid "$NEW") && [ -n "$pair" ] && pairs+=("$pair")
  else
    while read -r p; do
      [ -b "$p" ] || continue
      pair=$(regen_fs_uuid "$p") && [ -n "$pair" ] && pairs+=("$pair")
    done < <(lsblk -nrpo NAME,TYPE "$disk" | awk '$2=="part"{print $1}')
  fi

  if [ ${#pairs[@]} -gt 0 ]; then
    note "UUID map (old -> new):"
    for pair in "${pairs[@]}"; do note "  $pair" | sed 's/ / -> /'; done
    rewrite_uuid_refs "$ROOT" "${pairs[@]}"
  fi
  note "block done"
}

# --- main -------------------------------------------------------------------
case "$MODE" in
  first-boot) do_first_boot ;;
  generate)
    resolve_new
    do_generate_userspace
    do_block
    ;;
esac
note "complete"
