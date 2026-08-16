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
    # The layout itself is declared in ONE place: the canonical repart profiles
    # under files/repart/defs/ (tokenized @ARCH@/@DATE@/@SWAP@), staged into
    # {{ETC}} below by lookup and stamped at run time by stamp.sh.
    BDR_OS_PREFIX: "/os/superbfowle"
    BDR_HOME_PREFIX: "/home/superbfowle"
    BDR_ARCH: "{{ {'x86_64': 'amd64', 'aarch64': 'arm64'}[ansible_architecture] | default(ansible_architecture) }}"
    # Run-time date: the profile ships with a @DATE@ token; the bins stamp it
    # when formatting (env BDR_DATE, else `date +%Y%m%d` at run time), so a
    # rendered playbook never carries a stale date stamp.
    BDR_DATE_TOKEN: "@DATE@"
    BDR_DEFAULT_SUBVOL: "{{ BDR_OS_PREFIX }}/{{ BDR_ARCH }}/{{ BDR_DATE_TOKEN }}"

    PKGS:
      - systemd        # >=261 for BlockDeviceReplace=
      - btrfs-progs    # >=6.12 for DefaultSubvolume= (offline profile)
      - grub-pc        # BIOS/GPT bootloader (no UEFI/systemd-boot here, sigh)

    ENV:
      # Target disk to (re)partition. DANGER: its current contents are wiped.
      BDR_DISK: /dev/vda
      # Mountpoint of the running, single-device, volatile btrfs root.
      BDR_SOURCE_MOUNT: /
      # Subvolume layout (BDR_DEFAULT_SUBVOL carries the @DATE@ token —
      # bdr-migrate stamps it at run time for its slot.sh set-default).
      BDR_DEFAULT_SUBVOL: "{{ BDR_DEFAULT_SUBVOL }}"
      BDR_ARCH: "{{ BDR_ARCH }}"
      BDR_DATE_TOKEN: "{{ BDR_DATE_TOKEN }}"
      BDR_OS_PREFIX: "{{ BDR_OS_PREFIX }}"
      BDR_HOME_PREFIX: "{{ BDR_HOME_PREFIX }}"
      BDR_SWAP_SIZE: 4G
      # Shared repart toolkit instance (repart.opt.pb owns scripts AND defs).
      # pivot-bdr embeds NOTHING repart-related — it points here. Install it
      # with: ansible-playbook -i 'localhost,' -c local repart.opt.pb
      REPART_DIR: /opt/repart-main

    BINS:
      # tombstones: kit bins from the embed era — now owned by $REPART_DIR
      # (repart.opt.pb). Declared absent so older renders get cleaned up.
      - name: stamp.sh
        state: absent
      - name: repart.sh
        state: absent
      - name: slot.sh
        state: absent

      # NOTE: no repart scripts or defs are embedded here — they live in the
      # shared instance at $REPART_DIR (default /opt/repart-main, see ENV).
      # The bdr-* bins below are thin BDR-specific glue over that kit.

      # Pre-flight: verify the source root is migratable by BDR.
      - name: bdr-preflight.sh
        content: |
          # Confirm the running root is a single-device btrfs (BDR requires it)
          # and that repart is new enough.
          SRC="${BDR_SOURCE_MOUNT:-/}"
          REPART="${REPART_DIR:-/opt/repart-main}"
          [ -x "$REPART/bin/repart.sh" ] || {
            echo "Error: repart toolkit missing at $REPART (run repart.opt.pb)" >&2
            exit 1
          }

          if ! stat -f -c %T "$SRC" | grep -q btrfs; then
            echo "Error: $SRC is not btrfs (BlockDeviceReplace= is btrfs-only)" >&2
            exit 1
          fi

          ndev="$(btrfs filesystem show "$SRC" 2>/dev/null | grep -c 'devid')"
          if [ "$ndev" != "1" ]; then
            echo "Error: $SRC btrfs has $ndev devices; BDR needs exactly 1" >&2
            exit 1
          fi

          "$REPART/bin/repart.sh" check
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
          REPART="${REPART_DIR:-/opt/repart-main}"
          TOKEN="${BDR_DATE_TOKEN:-@DATE@}"
          DEFAULT_SUBVOL="${BDR_DEFAULT_SUBVOL:-}"
          # stamp the run-time date into any tokened template
          if case "$DEFAULT_SUBVOL" in *"$TOKEN"*) true ;; *) false ;; esac; then
            DATE="${BDR_DATE:-$(date +%Y%m%d)}"
            case "$DATE" in '' | *[!0-9]*) echo "Error: bad BDR_DATE '$DATE' (want YYYYMMDD)" >&2; exit 1 ;; esac
            DEFAULT_SUBVOL="${DEFAULT_SUBVOL//$TOKEN/$DATE}"
          fi
          SRC="${BDR_SOURCE_MOUNT:-/}"

          "{{BINS_DIR}}/bdr-preflight.sh"

          # repart.sh owns defs+flavor composition, stamping, and flags.
          # bdr flavor = universal layout with BlockDeviceReplace=/ root.
          export REPART_SCRATCH="{{DIR}}/var/tmp"
          export REPART_ARCH="${BDR_ARCH:-}"
          export REPART_SED="s|@SWAP@|${BDR_SWAP_SIZE:-4G}|g"
          export REPART_OS_PREFIX="${BDR_OS_PREFIX:-/os/superbfowle}"

          echo "=== DRY RUN first (no changes) ==="
          "$REPART/bin/repart.sh" dry-run "$DISK" --flavor bdr

          echo ""
          echo "!!! About to WIPE $DISK and migrate $SRC onto it. !!!"
          echo "Set BDR_CONFIRM=yes to proceed."
          [ "${BDR_CONFIRM:-no}" = "yes" ] || { echo "aborted (no confirm)"; exit 1; }
          export REPART_CONFIRM=yes
          "$REPART/bin/repart.sh" migrate "$DISK" --flavor bdr

          # Online BDR can't set the default subvolume; slot.sh does it:
          # the (stamped) $DEFAULT_SUBVOL if set+present, else newest slot
          # under the os prefix, else a soft skip. Empty/absent DEFAULT_SUBVOL
          # goes straight to newest — slot.sh owns the scheme.
          set +e
          "$REPART/bin/slot.sh" default "$SRC" "$DEFAULT_SUBVOL" >/dev/null 2>&1
          rc=$?
          set -e
          case $rc in
            0) : ;;
            *) "$REPART/bin/slot.sh" default "$SRC" \
                 || echo "note: no OS slot under $REPART_OS_PREFIX; skipping set-default" ;;
          esac

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
          REPART="${REPART_DIR:-/opt/repart-main}"
          # repart.sh composes the universal layout + format flavor (fresh
          # btrfs, dated slots) and stamps @DATE@/@ARCH@/@SWAP@ at run time.
          export REPART_SCRATCH="{{DIR}}/var/tmp"
          export REPART_DATE="${BDR_DATE:-}"
          export REPART_ARCH="${BDR_ARCH:-}"
          export REPART_SED="s|@SWAP@|${BDR_SWAP_SIZE:-4G}|g"
          "$REPART/bin/repart.sh" format "$TARGET" --flavor format

      # De-identify a clone (e.g. after btrfs send|receive of an image).
      # Now a raw copy of the canonical files/mkosi/identity.sh (whose default
      # --first-boot mode == the old clone-reset.sh behavior, plus --generate for
      # block UUID regen). Single source of truth lives in files/mkosi/.
      - name: clone-reset.sh
        src: ../mkosi/identity.sh
        raw: true

    README: |
      # pivot-bdr-main

      In-place disk migration via systemd-repart **BlockDeviceReplace=** (BDR):
      live-migrate a running single-device btrfs root onto a freshly-GPT'd
      disk (no reboot; reverts to the source device on failure). Partition
      mechanics come from the shared repart toolkit — run **repart.opt.pb
      first** so `/opt/repart-main` exists (bins point there via REPART_DIR).

      ## quick start

          # once: shared toolkit + this subsystem
          ansible-playbook -i 'localhost,' -c local repart.opt.pb
          ansible-playbook -i 'localhost,' -c local pivot-bdr.srv.pb
          . /srv/pivot-bdr-main/env.export

          # rehearse on an image file (zero risk)
          truncate -s 16G /var/tmp/rehearsal.img
          /srv/pivot-bdr-main/bin/bdr-format.sh /var/tmp/rehearsal.img
          loop=$(sudo losetup -fP --show /var/tmp/rehearsal.img)
          sudo btrfs subvolume list "$loop"       # dated OS + home slots
          sudo btrfs subvolume get-default "$loop"
          sudo losetup -d "$loop"

          # real target (WIPES IT)
          sudo /srv/pivot-bdr-main/bin/bdr-format.sh /dev/sda
          sudo mount /dev/sda4 /mnt               # root = last partition
          /opt/repart-main/bin/slot.sh verify /mnt

      ## detailed guide

      ### two paths

      - **bdr-format.sh** — offline, from-scratch: the universal layout (1M
        bios_grub, 384M ESP, fixed @SWAP@ swap, root LAST so later disk growth
        lands on it) + format flavor (btrfs with
        `/os/superbfowle/<arch>/<yyyymmdd>` default slot +
        `/home/superbfowle/<yyyymmdd>` home slot). For blank disks, images,
        rescue-env formatting. Needs nothing running.
      - **bdr-migrate.sh** — online BDR: the RUNNING root (a single-device
        btrfs on a VOLATILE device — zram/brd/kexec'd initrd root) is copied
        block-by-block onto the target via `btrfs replace`; the device-id is
        swapped atomically while mounted, then the fs is grown. To GET such a
        root on a single-disk VPS, kexec a rescue initrd first (see mkosi-git
        `vps-seed` / `debinst-kexec`).

      ### bins (`bin/`)

      | bin | what |
      |---|---|
      | `bdr-preflight.sh` | source is btrfs? single-device? repart >= 261? toolkit present? |
      | `bdr-format.sh <disk\|image>` | offline format (toolkit compose+stamp+run) |
      | `bdr-migrate.sh [disk]` | dry-run → `BDR_CONFIRM=yes` → online migrate → set default slot |
      | `bdr-grub.sh [disk]` | `grub-install` BIOS/GPT into the bios_grub partition |
      | `clone-reset.sh` | `identity.sh --first-boot` (de-identify a clone) |

      ### env (`env.export`)

      `BDR_DISK` target; `BDR_SOURCE_MOUNT` running btrfs root (default /);
      `BDR_DATE` slot stamp (default today); `BDR_ARCH`; `BDR_DEFAULT_SUBVOL`;
      `BDR_OS_PREFIX`/`BDR_HOME_PREFIX`; `BDR_SWAP_SIZE` (default 4G);
      `REPART_DIR` (default /opt/repart-main).

      ### slots & rollback

      Every system carries the same subvolumes — the layout is declared in ONE
      place (repo `files/repart/defs/format.d/50-root.conf`). New install =
      new dated slot; rollback = `slot.sh flip <yyyymmdd>`; inventory =
      `slot.sh list|verify`. Slots are never auto-deleted.

      ### mechanism constraints (repart.c)

      btrfs-only, single-device-only, ONLINE-only; `BlockDeviceReplace=` is
      incompatible with `Format=`/`CopyBlocks=`/`CopyFiles=` (the fs move IS
      the population); `DefaultSubvolume=` needs `--offline` — the opposite of
      BDR — so bdr-migrate sets the default subvolume via slot.sh afterwards.

  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: srv
