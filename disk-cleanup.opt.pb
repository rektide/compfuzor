---
- hosts: all
  vars:
    TYPE: disk-cleanup
    INSTANCE: main
    # Renders under /opt/disk-cleanup-main (vars/types/opt.yaml via the
    # .opt.pb suffix). Everything this playbook generates is unprivileged;
    # the only privileged step is the operator-time /etc link below.

    README: |
      # disk-cleanup

      > Post-incident (2026-10-01: root btrfs hit 100%, k3s crash-looped
      > on etcd fsync starvation) capture of the recurring ad-hoc ~/src +
      > journald + btrfs cleanup, as reviewable tooling.

      Nothing here runs automatically. `BINS_RUN_BYPASS: True` keeps the
      render inert; both scripts dry-run by default and need `--apply` to
      change anything.

      ## bin/

      - `src-clean.ts` — walks a source tree (default `$HOME/src`),
        reports reclaimable cargo `target/` innards (never whole `target/`)
        and whole `node_modules/` trees, with sizes and the exact commands
        it would run. `--apply` is the only deletion path. `--help`
        documents the pnpm store hardlink/reflink semantics: unlinking
        pnpm-managed `node_modules` frees almost nothing until
        `pnpm store prune` runs, while re-install stays cheap (re-link,
        no re-download) as long as the store holds the content.
      - `btrfs-balance.ts` — staged data-chunk balance for the root btrfs
        (`-dusage=2` → `8` → `20` → `45`, `--deep` appends `65`).
        Dry-run default; `--apply` needs root. Heavy IO: run idle, never
        during builds.

      ## etc/journald.conf.d/ — journald disk caps

      Drop-in linked (operator step) into `/etc/systemd/journald.conf.d/`.
      journald caps disk by BOTH size and time; systemd's size defaults
      are `SystemMaxUse=min(10% of fs, 4G)` (why /var/log/journal sat at
      4.1G on a 3.4T root) and `MaxRetentionSec=0` (keep forever). This
      drop-in sets `SystemMaxUse=1G`, `SystemKeepFree=4G`,
      `MaxRetentionSec=1month` — all playbook vars below.

      One-shot reclaim after linking (operator decision, not run by
      compfuzor):

          journalctl --vacuum-size=1G

      then `systemctl restart systemd-journald` (or `systemctl kill
      -s SIGUSR2 systemd-journald` to just flush) so the running daemon
      picks up the new caps.

      ## Privilege / bypass story

      The render writes only under /opt/disk-cleanup-main (no become).
      Linking the journald drop-in into /etc/systemd/journald.conf.d is
      the one privileged step and happens at operator time via the
      generated links tooling (auto-sudo when the dest is unwritable):

          sudo /opt/disk-cleanup-main/bin/install.sh
          # or: /opt/disk-cleanup-main/bin/links.mjs apply

      Bypass flags: `LINKS_BYPASS=True` drops the link plan entirely;
      `BINS_BYPASS=True` skips bin deployment; the usual
      `DIR_BYPASS`/`FS_BYPASS` pair skips the tree.

    # ---- journald caps (vars, not literals, so a run can retune) ----
    JOURNALD_SYSTEM_MAX_USE: 1G
    JOURNALD_SYSTEM_KEEP_FREE: 4G
    JOURNALD_MAX_RETENTION_SEC: 1month

    ETC_DIRS:
      - journald.conf.d
    ETC_FILES:
      - name: journald.conf.d/{{NAME}}.conf
        mode: "0644"
        content: |
          # managed by compfuzor {{NAME}} (disk-cleanup.opt.pb)
          # Caps journald's disk use. Defaults being overridden:
          #   SystemMaxUse  = min(10% of fs, 4G)  -> 4.1G of /var/log/journal on a 3.4T root
          #   MaxRetentionSec = 0 (retain forever)
          # See journald.conf(5); Runtime* variants apply to /run only.
          # One-shot reclaim after installing this drop-in (operator):
          #   journalctl --vacuum-size=1G
          [Journal]
          SystemMaxUse={{JOURNALD_SYSTEM_MAX_USE}}
          SystemKeepFree={{JOURNALD_SYSTEM_KEEP_FREE}}
          MaxRetentionSec={{JOURNALD_MAX_RETENTION_SEC}}

    # The /etc/systemd/journald.conf.d link: rendered into the LINKS plan
    # (files land in /etc/opt/{{NAME}}, exposed via DIR/etc). The actual
    # symlink is created by the operator (bin/install.sh or links.mjs,
    # which sudo-escalates for the unwritable /etc dest) — not during the
    # ansible pass. LINKS_BYPASS=True skips generating this plan.
    LINKS:
      - src: "{{ETC}}/journald.conf.d/{{NAME}}.conf"
        dest: "/etc/systemd/journald.conf.d/{{NAME}}.conf"
        scope: system

    # Toolkit deployed raw (verbatim, no templating) from files/disk-cleanup/
    # into {{BINS_DIR}}/ — same pattern as k3s's files/k3s-server bins.
    BINS:
      - name: src-clean.ts
        src: src-clean.ts
        raw: True
      - name: btrfs-balance.ts
        src: btrfs-balance.ts
        raw: True

    # Both bins are operator tools that dry-run by default; nothing to
    # execute during generation.
    BINS_RUN_BYPASS: True

  tasks:
    - import_tasks: tasks/compfuzor.includes
