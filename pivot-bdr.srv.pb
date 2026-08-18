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
#      BlockDeviceReplace=<source mount> to live-migrate the btrfs root via
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
# Canonical `format.d` and `bdr.d` overlays cannot share a root definition:
# format is offline and creates btrfs; BDR is online and renders its source.
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
    # repart.opt.pb and rendered at run time by `repart profile render`.
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
      # Subvolume layout (BDR_DEFAULT_SUBVOL carries the @DATE@ token;
      # bdr-migrate resolves it before calling `repart slot set`).
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
      # Old embedded public bins are tombstoned; repart.opt.pb owns one CLI.
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
          [ -x "$REPART/bin/repart" ] || {
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

          ver="$(systemd-repart --version | awk 'NR==1{print $2}')"
          [ "$ver" -ge 261 ] || { echo "Error: systemd-repart $ver < 261" >&2; exit 1; }
          echo "preflight OK: $SRC is single-device btrfs, repart $ver present" >&2
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

          export REPART_OS_PREFIX="${BDR_OS_PREFIX:-/os/superbfowle}"
          export REPART_HOME_PREFIX="${BDR_HOME_PREFIX:-/home/superbfowle}"
          args=(disk plan migrate "$DISK" --source "$SRC" --swap "${BDR_SWAP_SIZE:-4G}")
          [ -z "${BDR_ARCH:-}" ] || args+=(--arch "$BDR_ARCH")
          [ -z "${BDR_DATE:-}" ] || args+=(--date "$BDR_DATE")
          PLAN="$("$REPART/bin/repart" "${args[@]}")"
          echo "plan retained at $PLAN" >&2
          [ "${BDR_CONFIRM:-}" = "$DISK" ] || { echo "Set BDR_CONFIRM=$DISK to apply $PLAN" >&2; exit 1; }
          "$REPART/bin/repart" disk apply "$PLAN" --confirm "$DISK"

          # Online BDR can't set the default subvolume; the slot module does it:
          # the (stamped) $DEFAULT_SUBVOL if set+present, else newest slot
          # under the os prefix, else a soft skip. Empty/absent DEFAULT_SUBVOL
          # goes straight to newest — the slot module owns the scheme.
          set +e
          "$REPART/bin/repart" slot set "$SRC" "$DEFAULT_SUBVOL" >/dev/null 2>&1
          rc=$?
          set -e
          case $rc in
            0) : ;;
            *) "$REPART/bin/repart" slot set "$SRC" latest \
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

      # Offline path: format a fresh disk OR image file from format.d.
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
          export REPART_OS_PREFIX="${BDR_OS_PREFIX:-/os/superbfowle}"
          export REPART_HOME_PREFIX="${BDR_HOME_PREFIX:-/home/superbfowle}"
          args=(disk plan format "$TARGET" --swap "${BDR_SWAP_SIZE:-4G}")
          [ -z "${BDR_ARCH:-}" ] || args+=(--arch "$BDR_ARCH")
          [ -z "${BDR_DATE:-}" ] || args+=(--date "$BDR_DATE")
          PLAN="$("$REPART/bin/repart" "${args[@]}")"
          echo "plan retained at $PLAN" >&2
          [ "${BDR_CONFIRM:-}" = "$TARGET" ] || { echo "Set BDR_CONFIRM=$TARGET to apply $PLAN" >&2; exit 1; }
          "$REPART/bin/repart" disk apply "$PLAN" --confirm "$TARGET"

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

          ansible-playbook -i 'localhost,' -c local repart.opt.pb
          ansible-playbook -i 'localhost,' -c local pivot-bdr.srv.pb
          . /srv/pivot-bdr-main/env.export

          truncate -s 16G /var/tmp/rehearsal.img
          BDR_CONFIRM=/var/tmp/rehearsal.img \
            /srv/pivot-bdr-main/bin/bdr-format.sh /var/tmp/rehearsal.img
          sudo /opt/repart-main/bin/repart image with /var/tmp/rehearsal.img -- \
            sh -c '/opt/repart-main/bin/repart slot show "$REPART_MOUNT"'

          # Live migration plans first; confirmation applies that exact plan.
          BDR_CONFIRM=/dev/sda sudo -E /srv/pivot-bdr-main/bin/bdr-migrate.sh /dev/sda

      Both wrappers persist and preview a plan before applying it. Application
      requires `BDR_CONFIRM` to equal the target argument, binding ambient
      confirmation to one disk or image. Plans remain under
      `/opt/repart-main/var` (or `$REPART_DIR/var`) for audit.

      ### bins (`bin/`)

      | bin | what |
      |---|---|
      | `bdr-preflight.sh` | source is btrfs? single-device? repart >= 261? toolkit present? |
      | `bdr-format.sh <disk\|image>` | plan + apply canonical offline format |
      | `bdr-migrate.sh [disk]` | plan + confirmed online migration + set default slot |
      | `bdr-grub.sh [disk]` | `grub-install` BIOS/GPT into the bios_grub partition |
      | `clone-reset.sh` | `identity.sh --first-boot` (de-identify a clone) |

      ### env (`env.export`)

      `BDR_DISK` target; `BDR_SOURCE_MOUNT` running btrfs root (default /);
      `BDR_DATE` slot stamp (default today); `BDR_ARCH`; `BDR_DEFAULT_SUBVOL`;
      `BDR_OS_PREFIX`/`BDR_HOME_PREFIX`; `BDR_SWAP_SIZE` (default 4G);
      `REPART_DIR` (default /opt/repart-main).

      Slot inspection is `repart slot show MOUNT`; switching is
      `repart slot set MOUNT DATE|PATH|latest`. Data is stdout and mutation
      narration is stderr.

      ### mechanism constraints (repart.c)

      btrfs-only, single-device-only, ONLINE-only; `BlockDeviceReplace=` is
      incompatible with `Format=`/`CopyBlocks=`/`CopyFiles=` (the fs move IS
      the population); `DefaultSubvolume=` needs `--offline` — the opposite of
      BDR — so bdr-migrate sets the default subvolume through `repart slot set`.

  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: srv
