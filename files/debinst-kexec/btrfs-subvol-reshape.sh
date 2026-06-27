#!/bin/sh
# Reshape a fresh Debian btrfs install (everything in the top-level subvol,
# id 5) into an @-rooted layout with a separate @home, then pin subvol=@ in
# fstab and the grub kernel cmdline.
#
# Called from preseed/late_command as:  sh btrfs-subvol-reshape.sh /target
#
# Why: the d-i partman btrfs module installs into the top-level subvolume.
# Snapshot-friendly conventions (and tools like snapper/timeshift) expect the
# rootfs to live in a subvolume named @, with /home in @home. We do that move
# here, at the end of install, before the first reboot.
set -eu

TARGET="${1:-/target}"

# Device backing the new root (strip any [/subvol] suffix from /proc/mounts).
ROOT_SRC="$(awk -v t="$TARGET" '$2==t {print $1}' /proc/mounts | head -n1)"
ROOT_DEV="${ROOT_SRC%%[*}"
if [ -z "$ROOT_DEV" ] || [ ! -b "$ROOT_DEV" ]; then
    echo "reshape: could not determine root device for $TARGET" >&2
    exit 1
fi
echo "reshape: root device = $ROOT_DEV"

# Unmount the live install so we can work on the top level cleanly.
# (Anything under /target, deepest first.)
for m in $(awk -v t="$TARGET" '$2 ~ "^"t {print $2}' /proc/mounts | sort -r); do
    umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
done

# Mount the true top level (subvolid=5) to do the move.
TOP="$(mktemp -d)"
mount -o subvolid=5 "$ROOT_DEV" "$TOP"

# Create @ and move every top-level entry (incl. dotfiles) into it.
btrfs subvolume create "$TOP/@"
for entry in "$TOP"/* "$TOP"/.*; do
    base="$(basename "$entry")"
    case "$base" in
        '*' | '.*' | . | .. | @ ) continue ;;
    esac
    mv "$entry" "$TOP/@/"
done

# Split /home into its own subvolume so root snapshots don't drag user data.
btrfs subvolume create "$TOP/@home"
if [ -d "$TOP/@/home" ]; then
    # move existing /home contents into @home, then leave @/home as mountpoint
    for entry in "$TOP/@/home"/* "$TOP/@/home"/.*; do
        base="$(basename "$entry")"
        case "$base" in '*' | '.*' | . | .. ) continue ;; esac
        mv "$entry" "$TOP/@home/"
    done
    rmdir "$TOP/@/home" 2>/dev/null || rm -rf "$TOP/@/home"
fi
mkdir -p "$TOP/@/home"

# Make @ the default subvolume (belt-and-suspenders alongside fstab subvol=@).
NEWID="$(btrfs subvolume list "$TOP" | awk '$NF=="@"{print $2}')"
[ -n "$NEWID" ] && btrfs subvolume set-default "$NEWID" "$TOP"

# Remount the real rootfs (@) back at $TARGET so grub-install / fstab edits land.
umount "$TOP"
mount -o subvol=@ "$ROOT_DEV" "$TARGET"
mount -o subvol=@home "$ROOT_DEV" "$TARGET/home"

# Pin subvol=@ / @home explicitly in fstab (don't rely solely on set-default).
UUID="$(blkid -s UUID -o value "$ROOT_DEV")"
FSTAB="$TARGET/etc/fstab"
# Drop any btrfs root line d-i wrote, then re-add ours.
awk '!($2=="/" && $3=="btrfs") && !($2=="/home" && $3=="btrfs")' "$FSTAB" > "$FSTAB.new"
mv "$FSTAB.new" "$FSTAB"
{
    echo "UUID=$UUID /     btrfs defaults,subvol=@     0 0"
    echo "UUID=$UUID /home btrfs defaults,subvol=@home 0 0"
} >> "$FSTAB"

# Ensure the kernel mounts @ as root, regate grub, and rebuild.
echo 'GRUB_CMDLINE_LINUX="rootflags=subvol=@"' > "$TARGET/etc/default/grub.d/99-btrfs-subvol.cfg" 2>/dev/null || \
  echo 'GRUB_CMDLINE_LINUX="rootflags=subvol=@"' >> "$TARGET/etc/default/grub"

# Bind the API filesystems and regenerate bootloader + initramfs in-target.
for fs in proc sys dev dev/pts run; do
    mkdir -p "$TARGET/$fs"
    mount --bind "/$fs" "$TARGET/$fs" 2>/dev/null || true
done
chroot "$TARGET" update-grub
chroot "$TARGET" update-initramfs -u
for fs in run dev/pts dev sys proc; do
    umount "$TARGET/$fs" 2>/dev/null || umount -l "$TARGET/$fs" 2>/dev/null || true
done

echo "reshape: done — root=@ home=@home, subvol pinned in fstab + grub"
