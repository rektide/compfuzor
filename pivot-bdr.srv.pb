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

    # --- subvolume layout -----------------------------------------------------
    # Dated OS-slot scheme: the default subvol is a dated path under
    # /os/superbfowle/<arch>/, so a future install creates a NEW dated subvol
    # and flips the default (rollback = set-default back to the previous date).
    # BDR_SUBVOLS = every subvolume to create on the root btrfs.
    # BDR_SUBVOL_DEFAULT = which of them is mounted as / (must be in the list).
    BDR_ARCH: "{{ {'x86_64': 'amd64', 'aarch64': 'arm64'}[ansible_architecture] | default(ansible_architecture) }}"
    # Run-time date: the profile ships with a @DATE@ token; the bins stamp it
    # when formatting (env BDR_DATE, else `date +%Y%m%d` at run time), so a
    # rendered playbook never carries a stale date stamp.
    BDR_DATE_TOKEN: "@DATE@"
    BDR_SUBVOLS:
      - "/os/superbfowle/{{ BDR_ARCH }}/{{ BDR_DATE_TOKEN }}"   # dated OS slot = default
      - "/home/superbfowle/{{ BDR_DATE_TOKEN }}"                # dated home slot (mirrors mkosi's disk image)
    BDR_SUBVOL_DEFAULT: "{{ BDR_SUBVOLS | first }}"

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
      # Subvolume layout (rendered from BDR_SUBVOLS / BDR_SUBVOL_DEFAULT above;
      # BDR_DEFAULT_SUBVOL carries the @DATE@ token — bins stamp it at run time).
      BDR_DEFAULT_SUBVOL: "{{ BDR_SUBVOL_DEFAULT }}"
      BDR_SUBVOLUMES: "{{ BDR_SUBVOLS | join(' ') }}"
      BDR_ARCH: "{{ BDR_ARCH }}"
      BDR_DATE_TOKEN: "{{ BDR_DATE_TOKEN }}"
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
          # btrfs root with dated OS-slot subvolumes; default = BDR_SUBVOL_DEFAULT.
          # No SizeMaxBytes -> grows by weight to fill everything the swap
          # partition (fixed, below) does not claim.
          [Partition]
          Type=root
          Format=btrfs
          Label=root
          Subvolumes={{ BDR_SUBVOLS | join(' ') }}
          DefaultSubvolume={{ BDR_SUBVOL_DEFAULT }}
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
          TOKEN="${BDR_DATE_TOKEN:-@DATE@}"
          DEFAULT_SUBVOL="${BDR_DEFAULT_SUBVOL:-{{ BDR_SUBVOL_DEFAULT }}}"
          # stamp the run-time date into any tokened template
          if case "$DEFAULT_SUBVOL" in *"$TOKEN"*) true ;; *) false ;; esac; then
            DATE="${BDR_DATE:-$(date +%Y%m%d)}"
            case "$DATE" in '' | *[!0-9]*) echo "Error: bad BDR_DATE '$DATE' (want YYYYMMDD)" >&2; exit 1 ;; esac
            DEFAULT_SUBVOL="${DEFAULT_SUBVOL//$TOKEN/$DATE}"
          fi
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
          # The dated OS slot in the migrated fs was stamped when the source
          # image was formatted — which may be a different date than today.
          # So: prefer the (stamped) $DEFAULT_SUBVOL; if absent, fall back to
          # the newest subvol under its parent; if none, skip set-default.
          if ! btrfs subvolume show "$SRC/$DEFAULT_SUBVOL" >/dev/null 2>&1; then
            PARENT="$(dirname "$DEFAULT_SUBVOL")"
            found="$(btrfs subvolume list --sort=-ogen "$SRC" 2>/dev/null | awk -v p="${PARENT#/}/" 'index($NF, p"/")==1{print $NF; exit}')"
            if [ -n "$found" ]; then
              echo "note: $DEFAULT_SUBVOL absent; defaulting to newest slot /$found"
              DEFAULT_SUBVOL="/$found"
            else
              echo "note: no OS slot under $PARENT; skipping set-default"
              DEFAULT_SUBVOL=""
            fi
          fi
          if [ -n "$DEFAULT_SUBVOL" ]; then
            id="$(btrfs subvolume list "$SRC" | awk -v s="${DEFAULT_SUBVOL#/}" '$NF==s{print $2}')"
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
          # Usage: bdr-format.sh <disk-or-image>       (env: BDR_DATE=YYYYMMDD)
          set -eu
          TARGET="${1:?usage: bdr-format.sh <disk-or-image>}"
          DEFS="${BDR_SIMPLE_DEFS:-{{ETC}}/btrfs-simple.d}"
          TOKEN="${BDR_DATE_TOKEN:-@DATE@}"
          DATE="${BDR_DATE:-$(date +%Y%m%d)}"
          case "$DATE" in '' | *[!0-9]*) echo "Error: bad BDR_DATE '$DATE' (want YYYYMMDD)" >&2; exit 1 ;; esac

          mkdir -p "{{DIR}}/var/tmp"
          RUNDEFS="$(mktemp -d "{{DIR}}/var/tmp/bdr-defs.XXXXXX")"
          trap 'rm -rf "$RUNDEFS"' EXIT
          for f in "$DEFS"/*.conf; do
            sed "s|$TOKEN|$DATE|g" "$f" > "$RUNDEFS/$(basename "$f")"
          done
          echo "date stamp: $DATE  default subvol: $(awk -F= '/^DefaultSubvolume/{print $2; exit}' "$RUNDEFS"/50-root.conf)"

          systemd-repart \
            --definitions="$RUNDEFS" \
            --offline=yes \
            --empty=force \
            --dry-run=no \
            "$TARGET"
          echo "formatted $TARGET from $DEFS (date stamp $DATE)"

      # De-identify a clone (e.g. after btrfs send|receive of an image).
      # Now a raw copy of the canonical files/mkosi/identity.sh (whose default
      # --first-boot mode == the old clone-reset.sh behavior, plus --generate for
      # block UUID regen). Single source of truth lives in files/mkosi/.
      - name: clone-reset.sh
        src: ../mkosi/identity.sh
        raw: true

  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: srv
