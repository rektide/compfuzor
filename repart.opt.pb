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
      playbook installs the one CLI that creates that disk and navigates it.
      It is TypeScript; the playbook installs Node.js alongside it.

      ## the machine this manages

      Picture the target disk:

          GPT partition table
          ├── bios grub or ESP
          ├── swap (fixed size, before root so root stays last and growable)
          └── btrfs
              ├── os/superbfowle/amd64/20260817   <- a complete bootable OS
              ├── os/superbfowle/amd64/20260824   <- newer build, also bootable
              └── home/superbfowle/20260824       <- matching home directories

      The dated directories are btrfs subvolumes called **slots**. Which slot
      boots is a single btrfs property (the default subvolume), so switching —
      or rolling back to an older date — is instant and atomic. The toolkit's
      four namespaces each work on one part of this picture:

      | namespace | works on | commands |
      |---|---|---|
      | `profile` | tokenized config trees | `render` |
      | `disk` | the real disk: layout creation | `plan format\|migrate`, `apply` |
      | `image` | disk image *files* | `with` |
      | `slot` | the dated subvolumes | `path`, `show`, `set` |

      ## the core rule: plan, then apply

      Disk changes are always two steps, never one:

          $R disk plan format /dev/sda                  # touches nothing
          $R disk apply "$plan" --confirm /dev/sda      # does the damage

      `plan` renders the partition definitions, dry-runs systemd-repart,
      and persists a **plan directory**: the rendered definitions, the exact
      arguments, and a fingerprint of the target disk. `apply` re-verifies
      every piece and refuses to run if anything drifted.

      Why the ceremony? Because the persisted arguments include
      `--empty=force` — wipe. Think "review the diff, then commit", except
      the commit destroys a disk unless you name the same device twice and
      nothing about that device changed in between.

      ## why the commands are so long

      `repart disk plan format /dev/sda` is four decisions in a row:

      | word | decides |
      |---|---|
      | `repart` | the toolkit |
      | `disk` | the world: a real disk (vs `profile` config, `image` files, `slot` subvolumes) |
      | `plan` | the action: preview and persist (vs `apply`: execute) |
      | `format` | the variant: fresh offline layout (vs `migrate`: move a live btrfs root) |

      Each word is a real fork in the road, which is why the name is long.
      It is also the whole depth: nothing further hides below `format`.

      ## quick start

          ansible-playbook -i 'localhost,' -c local repart.opt.pb
          R=/opt/repart-main/bin/repart
          $R --help
          plan=$($R disk plan format /dev/sda --swap 8G)
          sudo $R disk apply "$plan" --confirm /dev/sda
          sudo $R image with image.raw -- \
            sh -c '/opt/repart-main/bin/repart slot show "$REPART_MOUNT"'

      Every namespace and operation answers `--help`, down to
      `repart disk plan --help`, with options, defaults, env vars, and
      examples inline.

      ## the other three namespaces in one breath

      `profile render --base DIR` copies a tree, overlays later trees on top,
      and stamps `@TOKEN@`s (`@DATE@`, `@ARCH@`, `@SWAP@`, `@OS_PREFIX@`,
      `@HOME_PREFIX@`, plus your own via `--set`), failing if any token
      survives unresolved. `disk plan` runs this same renderer over the
      canonical definitions in `etc/defs/` before previewing — the mermaid
      below is the entire internal call graph.

      `image with IMAGE -- CMD` attaches an image file to its own new loop
      device, finds the root partition (GPT root UUID, label fallback, or
      `--partition N`), mounts it privately, runs CMD with `REPART_IMAGE`,
      `REPART_LOOP`, `REPART_DEVICE`, `REPART_MOUNT` exported, then always
      unmounts and detaches — on success, failure, or Ctrl-C.

      `slot path 20260824` prints where a slot lives; `slot show MOUNT`
      lists slots as TSV with the default marked; `slot set MOUNT 20260817`
      changes which one boots.

      ```mermaid
      graph LR
        plan[disk plan] --> profile[profile render]
        apply[disk apply] --> plan
        image[image with]
        slot[slot path/show/set]
      ```

      ## durable state

      Rendered profiles and reviewed plans live under `/opt/repart-main/var`,
      never `/var/tmp`, and remain until explicitly removed — a plan you
      previewed last week is still there to audit or apply. Default names are
      descriptive (`format-disk.img-20260818T120000000Z-Ab3xYz`); pass
      `--name NAME` when another process needs a predictable path. Image
      mountpoints also live under `var`, but those are private resources
      `image with` always unmounts and removes itself.

      ## reference: stdout and ownership

      | command | stdout contract | ownership |
      |---|---|---|
      | `profile render` | final absolute rendered tree path only | durable under `DIR/var`; caller removes it explicitly; `--preserve RELPATH` leaves an opaque subtree tokenized |
      | `disk plan format\|migrate` | persistent absolute plan path only | durable under `DIR/var`; apply retains it for audit |
      | `disk apply` | no data | plan remains caller-owned |
      | `image with` | child stdout only | command owns and always cleans its new loop and private mountpoint |
      | `slot path\|show` | path or stable TSV data only | no temporary resources |
      | `slot set` | no data | mutation narration is stderr only |

      All diagnostics, dry-run output, and mutation narration go to stderr.

      ## reference: environment

      One precedence rule: flag > `REPART_*` variable > built-in default.

      | flag | variable | meaning |
      |---|---|---|
      | `--base` | `REPART_BASE` | profile base tree |
      | `--overlay` | `REPART_OVERLAY` (comma-separated) | overlay tree, later wins |
      | `--preserve` | `REPART_PRESERVE` (comma-separated) | leave subtree tokenized |
      | `--date` | `REPART_DATE` | DATE token (default: today) |
      | `--arch` | `REPART_ARCH` | ARCH token (default: mapped host arch) |
      | `--swap` | `REPART_SWAP` | SWAP token (default: 16G) |
      | `--set` | `REPART_SET` (comma-separated) | extra token NAME=VALUE |
      | `--name` | `REPART_NAME` | state directory name |
      | `--source` | `REPART_SOURCE` | migrate source mount |
      | `--confirm` | `REPART_CONFIRM` | apply confirmation target |
      | `--partition` | `REPART_PARTITION` | image partition number |
      | `--subvol` | `REPART_SUBVOL` | image subvolume |
      | `--read-only` | `REPART_READ_ONLY` (truthy) | read-only mount |
      | `path --home` | `REPART_HOME` (truthy) | home slot prefix |
      | — | `REPART_OS_PREFIX` / `REPART_HOME_PREFIX` | slot scheme prefixes (default `/os/superbfowle`, `/home/superbfowle`) |

      Positional arguments (targets, plans, mounts, commands) always stay
      explicit.

      ## reference: what apply enforces

      A plan directory contains rendered `definitions/`, the allowlisted
      repart `arguments`, target metadata in `plan`, and a `digest` over all
      reviewed inputs. Applying verifies the digest and the target
      fingerprint, requires the same canonical target via `--confirm`,
      rejects mounted devices and partitions, accepts no raw repart
      arguments, and executes the persisted arguments with only
      `--dry-run=yes` changed to `--dry-run=no`.

      `disk plan format` combines universal + format definitions and forces
      `--offline=yes`. `disk plan migrate` combines universal + BDR
      definitions, renders `BlockDeviceReplace=` from the canonical source
      mount, and requires systemd-repart 261+ with single-device btrfs.
      Profile defaults are today, mapped host architecture, 16G swap, and
      the OS/home prefixes shared with `slot`.
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt
