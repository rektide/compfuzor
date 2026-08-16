---
# repart-kit — standalone install of the shared repart/btrfs toolkit
# (files/repart/): stamp.sh (run-time @DATE@ stamping into on-disk scratch),
# repart.sh (invocation wrapper + systemd v261+ gate), slot.sh (dated OS/home
# slot lifecycle: list/default/flip/verify). The same scripts are embedded
# into pivot-bdr.srv.pb and mkosi.src.pb bins and burned into disk images via
# mkosi.extra; this playbook is for hosts that want them WITHOUT those
# subsystems (rescue box, spawned instance, dev loop).
- hosts: all
  vars:
    TYPE: repart-kit
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
    README: |
      # repart-kit

      Standalone install of the shared repart/btrfs toolkit. Canonical copies
      live in `files/repart/` of the compfuzor repo; pivot-bdr and mkosi embed
      the same files, so behavior is identical everywhere.

      | bin | what it does |
      |---|---|
      | `stamp.sh <src>...` | copy file/dir(s) (basename preserved) to on-disk scratch (`REPART_SCRATCH`, default `/var/tmp` — never tmpfs) and stamp `@DATE@` tokens at run time; echoes the scratch dir |
      | `repart.sh check\|dry-run\|format\|migrate` | systemd-repart wrapper: v261+ version gate, canonical flag combos; `format`/`migrate` are destructive, `migrate` needs `REPART_CONFIRM=yes` |
      | `slot.sh paths\|list\|default\|flip\|verify` | dated-slot lifecycle on a mounted btrfs; `default` falls back to newest slot, `flip` is the A/B rollback verb |

      Dated-slot scheme defaults (env-overridable): `REPART_OS_PREFIX=/os/superbfowle`,
      `REPART_HOME_PREFIX=/home/superbfowle`, `REPART_ARCH` from `uname -m`
      (x86_64→amd64, aarch64→arm64), `REPART_DATE` defaults to today.
  tasks:
    - import_tasks: tasks/compfuzor.includes
