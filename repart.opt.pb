---
- hosts: all
  vars:
    TYPE: repart
    INSTANCE: main
    DIRS:
      - libexec/repart
    BINS:
      - name: repart
        src: ../repart/repart
        raw: true
      - name: profile.sh
        dest: ../libexec/repart/profile.sh
        src: ../repart/libexec/profile.sh
        raw: true
      - name: disk.sh
        dest: ../libexec/repart/disk.sh
        src: ../repart/libexec/disk.sh
        raw: true
      - name: image.sh
        dest: ../libexec/repart/image.sh
        src: ../repart/libexec/image.sh
        raw: true
      - name: slot.sh
        dest: ../libexec/repart/slot.sh
        src: ../repart/libexec/slot.sh
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

      One public `repart` CLI backed by four private namespace helpers and the
      canonical partition definitions.

      ## quick start

          ansible-playbook -i 'localhost,' -c local repart.opt.pb
          R=/opt/repart-main/bin/repart
          plan=$($R disk plan format /dev/sda --swap 8G)
          sudo $R disk apply "$plan" --confirm /dev/sda
          sudo $R image with image.raw -- \
            sh -c '/opt/repart-main/bin/repart slot show "$REPART_MOUNT"'

      ## dependency graph

      ```mermaid
      graph LR
        disk[disk] --> profile[profile]
        image[image]
        slot[slot]
      ```

      `profile`, `image`, and `slot` are independent; only `disk` calls another
      module (`profile`). Helpers under `libexec/repart/` are private.

      ## stdout and ownership

      | command | stdout contract | ownership |
      |---|---|---|
      | `profile render` | final absolute rendered tree path only | caller owns and removes the tree; `--preserve RELPATH` copies an opaque subtree without resolving its deferred tokens |
      | `disk plan format\|migrate` | persistent absolute plan path only | caller owns; apply retains it for audit |
      | `disk apply` | no data | plan remains caller-owned |
      | `image with` | child stdout only | command owns and always cleans its new loop and private mountpoint |
      | `slot path\|show` | path or stable TSV data only | no temporary resources |
      | `slot set` | no data | mutation narration is stderr only |

      All diagnostics, dry-run output, and mutation narration go to stderr.
      Disk apply accepts no raw repart arguments, confirms the canonical target,
      revalidates its fingerprint, rejects mounted targets, and executes the
      persisted arguments with only `--dry-run=yes` changed to `--dry-run=no`.

      `disk plan format` always uses the canonical universal + format definitions
      and `--offline=yes`. `disk plan migrate` uses universal + BDR definitions,
      renders `BlockDeviceReplace=` from the canonical source mount, and requires
      systemd-repart 261+ with a single-device btrfs source. Profile defaults are
      today, mapped host architecture, 4G swap, and the same OS/home prefixes
      consumed by `slot` (`REPART_OS_PREFIX`, `REPART_HOME_PREFIX`).
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt
