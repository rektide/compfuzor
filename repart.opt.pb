---
# repart — shared systemd-repart + btrfs toolkit AND the canonical partition
# definitions. Installed as /opt/repart-main:
#   bin/{stamp,repart,slot}.sh      the kit verbs
#   etc/defs/universal.d/           the universal layout (bios_grub 1M, ESP
#                                   384M, fixed @SWAP@ swap, root LAST/growable)
#   etc/defs/{format,bdr}.d/        flavor overlays: format = fresh btrfs with
#                                   dated superbfowle slots; bdr = online
#                                   BlockDeviceReplace= (mutually exclusive
#                                   root mechanics -> only 50-root.conf differs)
# Consumers (pivot-bdr.srv.pb, mkosi.src.pb bins) POINT here via REPART_DIR
# instead of embedding — one runtime source of truth. The one deliberate
# exception: mkosi burns copies INTO images (mkosi.extra/) because a spawned
# instance is a separate machine and cannot point at a host path.
- hosts: all
  vars:
    TYPE: repart
    INSTANCE: main
    BINS:
      - name: stamp.sh
        src: ../repart/stamp.sh
        raw: true
      - name: repart.sh
        src: ../repart/repart.sh
        raw: true
      - name: slot.sh
        src: ../repart/slot.sh
        raw: true
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

      Shared repart/btrfs toolkit + canonical partition definitions. Canonical
      copies live in `files/repart/` of the compfuzor repo. Consumers point at
      this instance via `REPART_DIR=/opt/repart-main` (default) — they do NOT
      embed scripts or defs.

      ## quick start

          ansible-playbook -i 'localhost,' -c local repart.opt.pb
          R=/opt/repart-main
          $R/bin/repart.sh check                       # systemd-repart >= 261?
          $R/bin/repart.sh dry-run /dev/sda            # preview the WIPE plan, no writes
          sudo $R/bin/repart.sh format /dev/sda        # WIPE + universal layout
          sudo mount /dev/sda4 /mnt && $R/bin/slot.sh verify /mnt

          # swap size is a token; default resolves to 4G, override per run:
          sudo REPART_SWAP=8G $R/bin/repart.sh format /dev/sda

      ## detailed guide

      | path | what |
      |---|---|
      | `bin/stamp.sh <src>...` | copy to on-disk scratch (never tmpfs) + stamp `@DATE@`/`@ARCH@` (+ `REPART_SED`, e.g. `@SWAP@`); echoes scratch dir |
      | `bin/repart.sh check\|dry-run\|format\|migrate <target>` | compose defs+flavor -> stamp -> run systemd-repart (v261+ gate); `format`/`migrate` destructive, `migrate` needs `REPART_CONFIRM=yes`; `REPART_COMPOSE_ONLY=yes` prints the composed defs and exits |
      | `bin/slot.sh paths\|list\|default\|flip\|verify` | dated OS/home slot lifecycle on a mounted btrfs; `flip` is the A/B rollback verb |
      | `etc/defs/universal.d/` | universal GPT layout: 1M bios_grub (BIOS grub embed; harmless on UEFI), 384M ESP (harmless on BIOS), fixed `@SWAP@` swap, root last (grows; disk-growth tail lands on root) |
      | `etc/defs/format.d/`, `etc/defs/bdr.d/` | root flavors, overlaying `50-root.conf` wholesale — fresh btrfs slots vs online BDR are mechanically exclusive |

      Defs resolution in `repart.sh`: `REPART_DEFS`, else `<script>/../etc/defs/universal.d`
      (this install), else `/usr/local/share/repart-defs/universal.d` (burned into
      mkosi images). Dated-slot scheme env: `REPART_OS_PREFIX=/os/superbfowle`,
      `REPART_HOME_PREFIX=/home/superbfowle`, `REPART_ARCH`, `REPART_DATE`.
  tasks:
    - import_tasks: tasks/compfuzor.includes
