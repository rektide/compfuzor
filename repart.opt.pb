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

      `repart` builds a specific kind of machine: a disk whose root filesystem
      is a rack of dated, bootable OS snapshots you can switch between. This
      playbook installs the one CLI that creates that disk and manages it.
      It is TypeScript; the playbook installs Node.js alongside it.

      ## the machine this manages

      Picture the target disk:

          GPT partition table
          ├── bios grub or ESP
          ├── swap (fixed size, before root so root stays last and growable)
          └── btrfs
              ├── root/superbfowle/amd64/20260817   <- a complete bootable OS
              ├── root/superbfowle/amd64/20260824   <- newer build, also bootable
              └── home/superbfowle/20260824         <- matching home directories

      The dated directories are btrfs subvolumes. Which one boots is a single
      btrfs property (the default subvolume), so switching — or rolling back
      to an older date — is instant and atomic. The scheme is parameterized:
      base (`root` or `home`), flavor (default `superbfowle`), arch, date.

      ## the commands

      Nine flat commands, no nesting:

      | command | does |
      |---|---|
      | `render` | copy a tokenized tree, stamp `@TOKEN@s` |
      | `format` | dry-run a blank-disk layout; persist the draft |
      | `pivot` | dry-run a live-root migration; persist the draft |
      | `write` | execute a draft — the ONLY command that modifies a disk |
      | `loop-mount` | attach an image file, print its private mountpoint |
      | `loop-unmount` | tear down a `loop-mount` |
      | `subvol-path` | print where a dated subvolume lives |
      | `btrfs-subvols` | list dated subvolumes on a mounted filesystem |
      | `btrfs-default` | choose which subvolume boots |

      ## the core rule: draft, then write

      Disk changes are always two steps, never one:

          $R format /dev/sda                    # dry-run; touches nothing
          $R write "$draft" --confirm /dev/sda  # does the damage

      `format` renders the partition definitions, dry-runs systemd-repart,
      and persists a **draft**: the rendered definitions, the exact
      arguments, and a fingerprint of the target disk. `write` re-verifies
      every piece and refuses to run if anything drifted.

      Why the ceremony? Because the persisted arguments include
      `--empty=force` — wipe. Think "review the diff, then commit", except
      the commit destroys a disk unless you name the same device twice and
      nothing about that device changed in between.

      ## quick start

          ansible-playbook -i 'localhost,' -c local repart.opt.pb
          R=/opt/repart-main/bin/repart
          $R --help
          draft=$($R format /dev/sda --swap 8G)
          sudo $R write "$draft" --confirm /dev/sda
          mnt=$($R loop-mount image.raw)
          $R btrfs-subvols "$mnt"
          $R loop-unmount "$mnt"

      Every command answers `--help` with options, defaults, env vars, and
      examples inline.

      ## the commands in one breath

      `render --from DIR` copies a tree, overlays later trees on top, and
      stamps `@TOKEN@s` (`@DATE@`, `@ARCH@`, `@SWAP@`, `@ROOT_PREFIX@`,
      `@HOME_PREFIX@`, plus your own via `--set`), failing if any token
      survives unresolved. `format` and `pivot` run this same renderer over
      the canonical definitions in `etc/defs/` before previewing — the
      mermaid below is the entire internal call graph.

      `pivot TARGET --source MOUNT` moves a *running* btrfs root onto TARGET
      via systemd-repart BlockDeviceReplace: blocks copied, device swapped
      atomically while mounted, no reboot. Requires systemd-repart >=261
      and single-device btrfs.

      `loop-mount IMAGE` attaches an image file to its own new loop device,
      finds the root partition (GPT root type, label "root" fallback, or
      `--partition N`), and mounts it at a private path under `var/`,
      printing the mountpoint. `loop-unmount` reverses it: recursive umount,
      directory removed, loop detached. Two real commands instead of a
      `-- CMD` wrapper, so the mount survives shell exits. Image files only —
      a real disk is already a device node; mount it yourself.

      `subvol-path 20260824` prints where a dated subvolume lives (pure
      string computation); `btrfs-subvols MOUNT` lists them as TSV with the
      default marked; `btrfs-default MOUNT 20260817` changes which one
      boots.

      ```mermaid
      graph LR
        format[format] --> render[render]
        pivot[pivot] --> render
        write[write] --> draft[draft from format/pivot]
        loopmount[loop-mount] -.-> subvols[btrfs-subvols / btrfs-default]
      ```

      ## durable state

      Rendered trees and drafts live under `/opt/repart-main/var`, never
      `/var/tmp`, and remain until explicitly removed — a draft you previewed
      last week is still there to audit or write. Default names are
      descriptive (`format-disk.img-20260819T120000000Z-Ab3xYz`); pass
      `--name NAME` when another process needs a predictable path.
      `loop-mount` mountpoints also live under `var`, recorded in
      `var/mounts/` for `loop-unmount`.

      ## reference: stdout and ownership

      | command | stdout contract | ownership |
      |---|---|---|
      | `render` | rendered tree path only | durable under `DIR/var`; caller removes it explicitly; `--preserve RELPATH` leaves an opaque subtree tokenized |
      | `format` / `pivot` | draft path only | durable under `DIR/var`; write retains it for audit |
      | `write` | no data | draft remains caller-owned |
      | `loop-mount` | mountpoint path only | caller must `loop-unmount` when done |
      | `loop-unmount` | no data | reverses exactly one `loop-mount` |
      | `subvol-path` / `btrfs-subvols` | path or stable TSV only | no resources touched |
      | `btrfs-default` | no data | mutation narration is stderr only |

      All diagnostics, dry-run output, and mutation narration go to stderr.

      ## reference: environment

      One precedence rule: flag > `REPART_*` variable > built-in default.

      | flag | variable | meaning |
      |---|---|---|
      | `--from` | `REPART_FROM` | render source tree |
      | `--overlay` | `REPART_OVERLAY` (comma-separated) | overlay tree, later wins |
      | `--preserve` | `REPART_PRESERVE` (comma-separated) | leave subtree tokenized |
      | `--date` | `REPART_DATE` | DATE token (default: today) |
      | `--arch` | `REPART_ARCH` | arch segment (default: mapped host arch) |
      | `--swap` | `REPART_SWAP` | SWAP token (default: 16G) |
      | `--set` | `REPART_SET` (comma-separated) | extra token NAME=VALUE |
      | `--name` | `REPART_NAME` | state directory name |
      | `--source` | `REPART_SOURCE` | pivot source mount |
      | `--confirm` | `REPART_CONFIRM` | write confirmation target |
      | `--partition` | `REPART_PARTITION` | loop-mount partition number |
      | `--subvol` | `REPART_SUBVOL` | loop-mount subvolume |
      | `--read-only` | `REPART_READ_ONLY` (truthy) | read-only mount |
      | `--base` | `REPART_BASE` | subvol scheme base: root or home |
      | `--flavor` | `REPART_FLAVOR` | scheme flavor (default: superbfowle) |

      Positional arguments (targets, drafts, mounts) always stay explicit.

      ## reference: what write enforces

      A draft directory contains rendered `definitions/`, the allowlisted
      repart `arguments`, target metadata in `draft`, and a `digest` over all
      reviewed inputs. Writing verifies the digest and the target
      fingerprint, requires the same canonical target via `--confirm`,
      rejects mounted devices and partitions, accepts no raw repart
      arguments, and executes the persisted arguments with only
      `--dry-run=yes` changed to `--dry-run=no`.

      `format` combines universal + format definitions and forces
      `--offline=yes`. `pivot` combines universal + BDR definitions,
      renders `BlockDeviceReplace=` from the canonical source mount, and
      requires systemd-repart 261+ with single-device btrfs. Render
      defaults are today, mapped host architecture, 16G swap, and the
      root/home scheme prefixes built from the flavor.
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt
