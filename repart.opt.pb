---
- hosts: all
  vars:
    TYPE: repart
    INSTANCE: main
    DIRS:
      - var
    PKGS:
      - btrfs-progs
      - fdisk
      - nodejs
      - systemd
      - util-linux
    BINS:
      - name: repart
        src: ../repart/repart.ts
        raw: true
    BINS_ABSENT:
      - name: stamp.sh
      - name: compose.sh
      - name: repart.sh
      - name: loop.sh
      - name: slot.sh
    ETC_DIRS:
      - defs/universal.d
      - defs/format.d
      - defs/bdr.d
    ETC_FILES:
      - name: defs/universal.d/00-grub.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/00-grub.conf') }}"
      - name: defs/universal.d/10-esp.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/10-esp.conf') }}"
      - name: defs/universal.d/20-swap.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/20-swap.conf') }}"
      - name: defs/universal.d/50-root.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/50-root.conf') }}"
      - name: defs/format.d/50-root.conf
        content: "{{ lookup('file', '../../files/repart/defs/format.d/50-root.conf') }}"
      - name: defs/bdr.d/50-root.conf
        content: "{{ lookup('file', '../../files/repart/defs/bdr.d/50-root.conf') }}"
    README: |
      # repart-main

      One TypeScript `repart` CLI for rendering profiles, safely planning disk
      changes, working inside images, and selecting dated btrfs boot slots.
      The playbook installs Node.js, the CLI runtime, alongside the toolkit.

      ## quick start

          ansible-playbook -i 'localhost,' -c local repart.opt.pb
          R=/opt/repart-main/bin/repart
          plan=$($R disk plan format /dev/sda --swap 8G)
          sudo $R disk apply "$plan" --confirm /dev/sda
          sudo $R image with image.raw -- \
            sh -c '/opt/repart-main/bin/repart slot show "$REPART_MOUNT"'

      Start with `repart --help`. Every namespace and operation also supports
      `--help`, including `repart disk plan --help`; the CLI documents options,
      defaults, safety checks, ownership, and examples where they are needed.

      ## command model

      ```mermaid
      graph LR
        plan[disk plan] --> profile[profile render]
        apply[disk apply] --> plan
        image[image with]
        slot[slot path/show/set]
      ```

      `disk plan` renders the same profile model exposed by `profile render`.
      `image` and `slot` are independent tools for inspecting the result.

      ## durable state

      Rendered profiles and reviewed plans live under `/opt/repart-main/var`,
      never `/var/tmp`. A plan defaults to a descriptive name such as
      `format-disk.img-20260818T120000000Z-Ab3xYz`; use `--name NAME` when another process
      needs a predictable path. These artifacts remain until explicitly removed.
      The caller may `rm -rf` a rendered profile or plan after it is no longer
      needed. Image mountpoints also live under `var`, but are private resources
      that `image with` always unmounts and removes.

      ## environment

      One precedence rule: flag > `REPART_*` variable > built-in default.
      `REPART_BASE`, `REPART_OVERLAY` (comma-separated), `REPART_PRESERVE`
      (comma-separated), `REPART_DATE`, `REPART_ARCH`, `REPART_SWAP` (built-in
      default 16G), `REPART_SET` (comma-separated NAME=VALUE), `REPART_NAME`,
      `REPART_SOURCE`, `REPART_CONFIRM`, `REPART_PARTITION`, `REPART_SUBVOL`,
      `REPART_READ_ONLY` (truthy), `REPART_HOME` (truthy), plus the slot scheme
      prefixes `REPART_OS_PREFIX` and `REPART_HOME_PREFIX`. Positional arguments
      (targets, plans, mounts, commands) always stay explicit.

      ## stdout and ownership

      | command | stdout contract | ownership |
      |---|---|---|
      | `profile render` | final absolute rendered tree path only | durable under `DIR/var`; caller removes it explicitly; `--preserve RELPATH` leaves an opaque subtree tokenized |
      | `disk plan format\|migrate` | persistent absolute plan path only | durable under `DIR/var`; apply retains it for audit |
      | `disk apply` | no data | plan remains caller-owned |
      | `image with` | child stdout only | command owns and always cleans its new loop and private mountpoint |
      | `slot path\|show` | path or stable TSV data only | no temporary resources |
      | `slot set` | no data | mutation narration is stderr only |

      All diagnostics, dry-run output, and mutation narration go to stderr.
      Disk apply accepts no raw repart arguments, confirms the canonical target,
      revalidates its fingerprint, rejects mounted targets, and executes the
      persisted arguments with only `--dry-run=yes` changed to `--dry-run=no`.

      ### What each plan contains

      A plan directory contains rendered `definitions/`, the allowlisted repart
      `arguments`, target metadata in `plan`, and a `digest` over all reviewed
      inputs. Planning records the canonical target and a device/table
      fingerprint. Applying verifies the digest and fingerprint, requires the
      same canonical target via `--confirm`, rejects mounted devices and
      partitions, and changes only `--dry-run=yes` to `--dry-run=no`.

      `disk plan format` combines universal + format definitions and forces
      `--offline=yes`. `disk plan migrate` combines universal + BDR definitions,
      renders `BlockDeviceReplace=` from the canonical source mount, and requires
      systemd-repart 261+ with single-device btrfs. Profile defaults are today,
      mapped host architecture, 16G swap, and the OS/home prefixes shared with
      `slot` (`REPART_OS_PREFIX`, `REPART_HOME_PREFIX`).
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt
