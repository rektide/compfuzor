---
- hosts: all
  vars:
    TYPE: disk-cleanup
    INSTANCE: main
    # Renders under /opt/disk-cleanup-main (vars/types/opt.yaml via the
    # .opt.pb suffix). One subsystem, one bin per clean (operator decision
    # 2026-10-01: explicitly NOT a playbook per clean). The compfuzor
    # status.sh stays the subsystem status; the pnpm-prune timer adds a
    # reciprocal per-clean status via `systemctl --user status`.

    README: |
      # disk-cleanup

      > Post-incident (2026-10-01: root btrfs hit 100%, k3s crash-looped
      > on etcd fsync starvation) capture of the recurring ad-hoc ~/src +
      > journald + btrfs cleanup, as reviewable tooling.

      Nothing destructive runs automatically. `BINS_RUN_BYPASS: True`
      keeps the render inert; every bin dry-runs by default and needs
      `--apply` — the single sanctioned exception is the pnpm-prune timer
      below, whose weekly schedule IS the operator's standing approval.

      ## bin/ (one clean per bin)

      - `src-clean.ts` — default pass: rust-safe cargo `target/` innards
        only (`incremental/`, `package/`, `doc/`; never whole `target/`,
        never the build cache). `--node-modules` (opt-in anti-feature)
        also removes whole `node_modules/` trees — pnpm trees are store
        hardlinks, so that rarely frees bytes; it exists for dirent/inode
        bloat and broken trees. `--help` documents the pnpm store
        semantics.
      - `rust-aggressive.ts` — the `target/<profile>/{deps,build,
        .fingerprint}` sweep split out of src-clean: it FORCES FULL
        REBUILDS of every touched workspace. Run when reclaim is needed
        now and the machine is idle; otherwise src-clean.
      - `pnpm-prune.ts` — `pnpm store prune` wrapper (measured 2026-10-01:
        6.0 GB / 140,780 files freed). Dry-run default; the timer below
        runs it weekly with --apply.
      - `rustup-clean.ts` — keeper-policy toolchain cleanup: always keep
        default + active + N newest stables + N newest nightlies (2 each
        by default) + `--keep` globs; everything else is a candidate
        (24.1 GiB / 20 toolchains on first scan). Custom/linked channels
        always kept.
      - `btrfs-balance.ts` — staged data-chunk balance (2→8→20→45, `--deep`
        adds 65, `--dusage-cap N` stops the chain early). Host finding
        2026-10-01: stages 2/8/20 relocated 0/0/1 of 3340 chunks — this
        fs has NO sparse chunks; balance is a null lever here until big
        deletions (src-clean passes, toolchain uninstalls) re-sparse
        chunks. Re-run the cheap stages after those, never 45/65 absent
        new evidence.
      - `archive-large.ts` — READ-ONLY ~/archive reporter (no deletion
        path, no --apply): `<org>/<repo>` dirs over a threshold (default
        2G) plus org subtotals; per-hit largest-entries drill-down is
        opt-in via `--top N` and floors entries at 50M (`--min-child`;
        default off, operator preference 2026-10-14: the detail was
        noise and sub-50M entries irrelevant). First scan 2026-10-14: 11 of
        6210 repos held 43.3 of 240.8 GiB (anomalyco/opencode 11.9G —
        half of it node_modules/ plus two dead .jj.*ghost/backup trees;
        zen-browser .git 5.7G); the opencode ghosts + node_modules and
        zen-browser were deleted by the operator the same day. Added
        after the whole-target hollowing ask was measured a near-noop
        (src-clean + rust-aggressive already cover 11.1 of 11.6 GiB
        across 138 ~/src targets; node_modules declined per pnpm store
        semantics). Grouped by workspace status since 2026-10-18
        (operator policy: archive keeps repos we hold jj workspaces
        for; plain git clones are the move pool to
        /mnt/bitblaster/archive — nanomachine NFSv4.2, identically
        pathed on both hosts — with the old path symlinked back). Hits
        report per kind (no-.jj candidates / with-.jj keep-local /
        no-marker inspect), repo symlinks into /mnt/bitblaster count as
        already moved, and their NFS-side bytes are deliberately not
        walked: the report is the local disk's truth.
      - `lib.ts` — shared helpers (imported by the bins; not a command).

      Status: `bin/status.sh` (subsystem) and, for the scheduled clean,
      `systemctl --user status disk-cleanup-main-pnpm-prune.{service,timer}`.

      ## Weekly pnpm store prune (systemd --user)

      `{{NAME}}-pnpm-prune.{service,timer}` render as USER units and link
      into `~/.config/systemd/user/` — no sudo needed:

          systemctl --user enable --now disk-cleanup-main-pnpm-prune.timer
          systemctl --user list-timers disk-cleanup-main-pnpm-prune.timer

      The timer (OnCalendar=weekly, Persistent=true) fires while the user
      has a session. enable-linger was explicitly DECLINED by the
      operator: do not enable it — this box runs always-on user sessions,
      so the weekly cadence holds without it. The service's ExecStart
      passes `--apply` (the schedule is the sanction; interactive runs
      stay dry-run).

      ## etc/journald.conf.d/ — journald disk caps (LIVE since 2026-10-01)

      Drop-in live at `/etc/systemd/journald.conf.d/{{NAME}}.conf` with
      `SystemMaxUse=2G` (operator-picked), `SystemKeepFree=4G`,
      `MaxRetentionSec=1month`. Vacuum already run (freed 2G; journal
      2.1G). journald caps disk by BOTH size and time; systemd's size
      defaults are `SystemMaxUse=min(10% of fs, 4G)` (why /var/log/journal
      sat at 4.1G on a 3.4T root) and `MaxRetentionSec=0` (keep forever).
      One-shot reclaim after changing values (operator decision, not
      automated):

          journalctl --vacuum-size=2G
          sudo systemctl restart systemd-journald

      ## Privilege / bypass story

      The render writes only under /opt/disk-cleanup-main (no become).
      Two operator-time steps exist, each with its own gate:
      - the /etc journald link (privileged): `sudo bin/install.sh` or
        `bin/links.mjs apply` (auto-sudo for the unwritable /etc dest);
        `LINKS_BYPASS=True` skips generating the plan.
      - the user units (unprivileged): `bin/install.sh` units lane links
        them into `~/.config/systemd/user/` and enables the timer via
        `systemctl --user` — no linger, no sudo.
      `BINS_BYPASS=True` skips bin deployment; the usual
      `DIR_BYPASS`/`FS_BYPASS` pair skips the tree.

    # ---- journald caps (vars, not literals, so a run can retune) ----
    # SystemMaxUse retuned to 2G by the operator 2026-10-01 (postmortem
    # headroom over the original 1G); drop-in live on the host since.
    JOURNALD_SYSTEM_MAX_USE: 2G
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
          #   journalctl --vacuum-size=2G
          [Journal]
          SystemMaxUse={{JOURNALD_SYSTEM_MAX_USE}}
          SystemKeepFree={{JOURNALD_SYSTEM_KEEP_FREE}}
          MaxRetentionSec={{JOURNALD_MAX_RETENTION_SEC}}

    # The /etc/systemd/journald.conf.d link: rendered into the LINKS plan
    # (files land in /etc/opt/{{NAME}}, exposed via DIR/etc). The actual
    # symlink is created by the operator (bin/install.sh or links.mjs,
    # which sudo-escalates for the unwritable /etc dest) — not during the
    # ansible pass. LINKS_BYPASS=True skips generating this plan. Scope
    # stays system even though the units below are user scope.
    LINKS:
      - src: "{{ETC}}/journald.conf.d/{{NAME}}.conf"
        dest: "/etc/systemd/journald.conf.d/{{NAME}}.conf"
        scope: system

    # ---- weekly pnpm store prune: systemd USER units ----
    # SYSTEMD_SCOPE/INSTALL: user makes the install specs user-only: unit
    # files land in ETC, LINKS records point at ${HOME}/.config/systemd/
    # user (a runtime root links.mjs expands — no sudo), and the generated
    # install-*-user.sh bins drive `systemctl --user`. No top-level
    # SYSTEMD_* sections, so nothing leaks into the root dicts. The
    # operator explicitly DECLINED enable-linger: the timer fires while
    # the user has a session (always-on sessions here).
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    SYSTEMD_ROOTS:
      - pnpmPruneService
      - pnpmPruneTimer
    pnpmPruneService:
      SYSTEMD_SERVICE: "{{NAME}}-pnpm-prune"
      # the timer activates this unit; installing only links the file
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        Description: "{{NAME}} weekly pnpm store prune"
      SYSTEMD_SERVICES:
        Type: oneshot
        # The schedule IS the apply (operator sanction 2026-10-01); the
        # bin itself still dry-runs without the flag for interactive use.
        ExecStart: "{{DIR}}/bin/pnpm-prune.ts --apply"
    pnpmPruneTimer:
      SYSTEMD_TIMER: "{{NAME}}-pnpm-prune"
      SYSTEMD_UNITS:
        Description: "Weekly {{NAME}} pnpm store prune"
      SYSTEMD_TIMERS:
        OnCalendar: weekly
        Persistent: true
        Unit: "{{NAME}}-pnpm-prune.service"
      SYSTEMD_INSTALLS:
        WantedBy: timers.target

    # Toolkit deployed raw (verbatim, no templating) from files/disk-cleanup/
    # into {{BINS_DIR}}/ — same pattern as k3s's files/k3s-server bins.
    # lib.ts is a shared module imported by the bins (explicit .ts imports,
    # node type stripping), not a command itself.
    BINS:
      - name: lib.ts
        src: lib.ts
        raw: True
      - name: src-clean.ts
        src: src-clean.ts
        raw: True
      - name: rust-aggressive.ts
        src: rust-aggressive.ts
        raw: True
      - name: pnpm-prune.ts
        src: pnpm-prune.ts
        raw: True
      - name: rustup-clean.ts
        src: rustup-clean.ts
        raw: True
      - name: btrfs-balance.ts
        src: btrfs-balance.ts
        raw: True
      - name: archive-large.ts
        src: archive-large.ts
        raw: True

    # All bins are operator tools that dry-run by default (the pnpm-prune
    # timer's --apply is in its unit, not here); nothing to execute during
    # generation.
    BINS_RUN_BYPASS: True

  tasks:
    - import_tasks: tasks/compfuzor.includes
