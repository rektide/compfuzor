---
# ============================================================================
# pivot-bdr — in-place disk migration via systemd-repart BlockDeviceReplace=
#
# STATUS: SKETCH / UNVALIDATED. Needs systemd v261+ (Debian sid has it).
#         Every BIN here is destructive or near it; read before running.
#
# THE IDEA (the no-reboot, systemd-native replacement for pivot-root.opt.pb):
#   1. Build a modest Debian *btrfs* image (mkosi.src.pb) — single-device.
#   2. kexec into it so the running OS root is a btrfs on a VOLATILE block
#      device (RAM: zram/brd, or the kexec'd installer's in-memory device).
#   3. systemd-repart writes a fresh GPT onto the real disk and uses
#      BlockDeviceReplace=/ to LIVE-MIGRATE the running btrfs root onto it via
#      the kernel BTRFS_IOC_DEV_REPLACE ioctl (== `btrfs replace`): every block
#      is copied and the device-id is atomically swapped while mounted, then
#      grown to fill. No reboot. Reverts to the source device on failure.
#   4. set default subvolume, install grub (BIOS/GPT), de-identify, reboot.
#
# MECHANISM CONSTRAINTS (confirmed in src/repart/repart.c):
#   - btrfs only; SINGLE-DEVICE only (multi-device -> EOPNOTSUPP)
#   - ONLINE only: BlockDeviceReplace= is incompatible with --offline=yes
#   - cannot combine with Format=/CopyBlocks=/CopyFiles= (the fs move IS the
#     population step)
#   - DefaultSubvolume= needs --offline=yes (btrfs-progs >=6.12), i.e. the
#     OPPOSITE of BDR -> in the online flow set the default subvol by hand
#
# Two repart profiles ship here because offline-format and online-BDR cannot
# share a root definition:
#   btrfs-simple.d/  offline, from-scratch format (Format=btrfs + subvols)
#   btrfs-bdr.d/     online migrate (root uses BlockDeviceReplace=/ )
#
# No bios_grub type alias exists; we use the raw BIOS Boot Partition GUID
# 21686148-6449-6E6F-744E-656564454649 for grub's 1MiB embed area.
# ============================================================================
- hosts: all
  vars:
    TYPE: pivot-bdr
    INSTANCE: main
    BINS_RUN_BYPASS: True

    PKGS:
      - systemd        # >=261 for BlockDeviceReplace=
      - btrfs-progs    # >=6.12 for DefaultSubvolume= (offline profile)
      - grub-pc        # BIOS/GPT bootloader (no UEFI/systemd-boot here, sigh)

    ENV:
      # Target disk to (re)partition. DANGER: its current contents are wiped.
      BDR_DISK: /dev/vda
      # Mountpoint of the running, single-device, volatile btrfs root.
      BDR_SOURCE_MOUNT: /
      # Profile definition dirs (staged under {{ETC}}).
      BDR_SIMPLE_DEFS: "{{ETC}}/btrfs-simple.d"
      BDR_BDR_DEFS: "{{ETC}}/btrfs-bdr.d"
      # Subvolume layout.
      BDR_DEFAULT_SUBVOL: "@"
      BDR_SWAP_SIZE: 4G

    ETC_DIRS:
      - btrfs-simple.d
      - btrfs-bdr.d

    ETC_FILES:
      # ---- offline, from-scratch full-disk format profile -----------------
      - name: btrfs-simple.d/00-grub.conf
        content: |
          # 1MiB BIOS Boot Partition: grub embeds core.img here (no filesystem).
          [Partition]
          Type=21686148-6449-6E6F-744E-656564454649
          Label=grub-bios
          SizeMinBytes=1M
          SizeMaxBytes=1M

      - name: btrfs-simple.d/50-root.conf
        content: |
          # btrfs root with @ / @home subvolumes, @ as default.
          # No SizeMaxBytes -> grows by weight to fill everything the swap
          # partition (fixed, below) does not claim.
          [Partition]
          Type=root
          Format=btrfs
          Label=root
          Subvolumes=/@ /@home
          DefaultSubvolume=/@
          GrowFileSystem=yes
          SizeMinBytes=8G

      - name: btrfs-simple.d/90-swap.conf
        content: |
          # Fixed 4G swap, placed last (filename sort = on-disk order).
          [Partition]
          Type=swap
          Format=swap
          Label=swap
          SizeMinBytes=4G
          SizeMaxBytes=4G

      # ---- online BlockDeviceReplace= migrate profile ---------------------
      - name: btrfs-bdr.d/00-grub.conf
        content: |
          [Partition]
          Type=21686148-6449-6E6F-744E-656564454649
          Label=grub-bios
          SizeMinBytes=1M
          SizeMaxBytes=1M

      - name: btrfs-bdr.d/50-root.conf
        content: |
          # Root is NOT formatted here: the running btrfs at BlockDeviceReplace=
          # is live-migrated onto this partition via `btrfs replace`. repart
          # grows it to fill afterwards. Default subvolume is set post-migrate
          # by the bin (DefaultSubvolume= would require --offline=yes).
          [Partition]
          Type=root
          Label=root
          BlockDeviceReplace=/
          SizeMinBytes=8G

      - name: btrfs-bdr.d/90-swap.conf
        content: |
          [Partition]
          Type=swap
          Format=swap
          Label=swap
          SizeMinBytes=4G
          SizeMaxBytes=4G

    BINS:
      # Pre-flight: verify the source root is migratable by BDR.
      - name: bdr-preflight.sh
        content: |
          # Confirm the running root is a single-device btrfs (BDR requires it)
          # and that repart is new enough.
          SRC="${BDR_SOURCE_MOUNT:-/}"

          if ! stat -f -c %T "$SRC" | grep -q btrfs; then
            echo "Error: $SRC is not btrfs (BlockDeviceReplace= is btrfs-only)" >&2
            exit 1
          fi

          ndev="$(btrfs filesystem show "$SRC" 2>/dev/null | grep -c 'devid')"
          if [ "$ndev" != "1" ]; then
            echo "Error: $SRC btrfs has $ndev devices; BDR needs exactly 1" >&2
            exit 1
          fi

          if ! systemd-repart --help 2>&1 | grep -q -- '--definitions'; then
            echo "Error: systemd-repart missing/old (need v261+ for BDR)" >&2
            exit 1
          fi
          echo "preflight OK: $SRC is single-device btrfs, repart present"
          echo "source device: $(btrfs filesystem show "$SRC" | awk '/devid/{print $NF}')"

      # The migration itself. DESTROYS everything on $BDR_DISK.
      - name: bdr-migrate.sh
        content: |
          # Live-migrate the running btrfs root onto $BDR_DISK with a fresh GPT
          # (grub-bios + root + 4G swap), no reboot.
          #
          # Usage: bdr-migrate.sh [disk]
          set -eu
          DISK="${1:-${BDR_DISK:-/dev/vda}}"
          DEFS="${BDR_BDR_DEFS:-{{ETC}}/btrfs-bdr.d}"
          DEFAULT_SUBVOL="${BDR_DEFAULT_SUBVOL:-@}"
          SRC="${BDR_SOURCE_MOUNT:-/}"

          "{{BINS_DIR}}/bdr-preflight.sh"

          echo "=== DRY RUN first (no changes) ==="
          systemd-repart --definitions="$DEFS" --dry-run=yes "$DISK"

          echo ""
          echo "!!! About to WIPE $DISK and migrate $SRC onto it. !!!"
          echo "Set BDR_CONFIRM=yes to proceed."
          [ "${BDR_CONFIRM:-no}" = "yes" ] || { echo "aborted (no confirm)"; exit 1; }

          # --empty=force: create a brand new GPT, discarding the existing
          # (ext4) table. --dry-run=no: actually do it. Online (no --offline).
          systemd-repart \
            --definitions="$DEFS" \
            --empty=force \
            --dry-run=no \
            "$DISK"

          # Online BDR can't set the default subvolume; do it now.
          # (Assumes @ exists in the migrated fs; create if the source image
          # didn't already use an @ layout.)
          if ! btrfs subvolume show "$SRC/$DEFAULT_SUBVOL" >/dev/null 2>&1; then
            echo "note: $DEFAULT_SUBVOL subvol not present; skipping set-default"
          else
            id="$(btrfs subvolume list "$SRC" | awk -v s="$DEFAULT_SUBVOL" '$NF==s{print $2}')"
            [ -n "$id" ] && btrfs subvolume set-default "$id" "$SRC"
          fi

          echo "Migration done. Root now lives on $DISK. Install grub next:"
          echo "  bdr-grub.sh $DISK"

      # Install grub for BIOS/GPT (embeds into the 1MiB bios_grub partition).
      - name: bdr-grub.sh
        content: |
          set -eu
          DISK="${1:-${BDR_DISK:-/dev/vda}}"
          if [ ! -d /sys/firmware/efi ]; then
            grub-install --target=i386-pc --recheck "$DISK"
          else
            echo "warning: system is UEFI; this profile is BIOS/GPT only" >&2
            exit 1
          fi
          update-grub
          echo "grub installed to $DISK (BIOS/GPT)"

      # Offline path: format a fresh disk OR image file from btrfs-simple.d.
      - name: bdr-format.sh
        content: |
          # Lay down grub-bios + btrfs(@/@home) + swap on an empty target.
          # Use for mkosi-style images or rescue-env formatting (NOT for the
          # running root; that is bdr-migrate.sh).
          #
          # Usage: bdr-format.sh <disk-or-image>
          set -eu
          TARGET="${1:?usage: bdr-format.sh <disk-or-image>}"
          DEFS="${BDR_SIMPLE_DEFS:-{{ETC}}/btrfs-simple.d}"
          systemd-repart \
            --definitions="$DEFS" \
            --offline=yes \
            --empty=force \
            --dry-run=no \
            "$TARGET"
          echo "formatted $TARGET from $DEFS"

      # De-identify a clone (e.g. after btrfs send|receive of an image).
      - name: clone-reset.sh
        content: |
          # Make a cloned rootfs unique on first boot.
          #
          # WHY machine-id is fiddly (the "delete didn't always work" memory):
          #   systemd regenerates /etc/machine-id only when it is EMPTY or the
          #   literal "uninitialized\n" -- not when absent. A missing file can
          #   wedge early boot, and a baked-in id (initrd/UKI) or a stale
          #   /var/lib/dbus/machine-id keeps the old identity. So: truncate to
          #   empty (don't delete) and clear the dbus id + ssh host keys too.
          #
          # Usage: clone-reset.sh [rootdir]   (default /)
          set -eu
          R="${1:-/}"

          : > "$R/etc/machine-id"                      # empty -> regenerate
          rm -f "$R/var/lib/dbus/machine-id"           # dbus id (often a symlink)
          rm -f "$R"/etc/ssh/ssh_host_*                # regenerate host keys
          rm -f "$R"/etc/cloud/cloud-init.disabled 2>/dev/null || true

          # Mark a first boot so systemd-firstboot / ConditionFirstBoot fire.
          if [ "$R" = "/" ] && command -v systemd-firstboot >/dev/null 2>&1; then
            systemd-firstboot --reset || true
          fi
          echo "clone-reset: machine-id/dbus/ssh host keys cleared under $R"
          echo "they regenerate on next boot; verify with: systemd-id128 machine-id"

  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: srv
