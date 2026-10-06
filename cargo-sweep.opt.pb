---
- hosts: all
  vars:
    TYPE: cargo-sweep
    INSTANCE: main
    USERMODE: true
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    BINS_RUN_BYPASS: true

    RUST_STORAGE_MISE_BIN: /usr/bin/mise
    CARGO_SWEEP_VERSION: 0.8.0
    CARGO_SWEEP_TOOL: "cargo:cargo-sweep@{{CARGO_SWEEP_VERSION}}"
    CARGO_SWEEP_SRC_ROOT: "{{HOMEDIR}}/src"
    CARGO_SWEEP_ARCHIVE_ROOT: "{{HOMEDIR}}/archive"
    CARGO_SWEEP_SRC_DAYS: 14
    CARGO_SWEEP_ARCHIVE_DAYS: 30
    CARGO_SWEEP_SRC_CALENDAR: Mon,Thu *-*-* 03:00:00
    CARGO_SWEEP_ARCHIVE_CALENDAR: '*-*-01 04:00:00'
    CARGO_SWEEP_LOCK: "{{XDG_STATE_HOME}}/compfuzor/cargo-sweep.lock"

    README: |
      # cargo-sweep: age-based Rust artifact reclamation

      Rendering is inert and user-only. Run `bin/build.sh` explicitly to
      install `{{CARGO_SWEEP_TOOL}}` with mise's cargo backend (locked by
      default), then link `bin/cargo-sweep` directly to the executable.
      Installation can compile this small tool; it is never run by a timer.
      Version, exact tool spec and absolute RUST_STORAGE_MISE_BIN are overridable.

      Preview `bin/sweep.sh src` or `bin/sweep.sh archive`; the default includes
      --dry-run --verbose. Only explicit `--apply` deletes. A missing requested
      root fails loudly. Roots/ages/calendars are configurable at render time.
      Defaults are `{{CARGO_SWEEP_SRC_ROOT}}` older than {{CARGO_SWEEP_SRC_DAYS}}
      days Mon/Thu 03:00, and `{{CARGO_SWEEP_ARCHIVE_ROOT}}` older than
      {{CARGO_SWEEP_ARCHIVE_DAYS}} days on the first of each month at 04:00.

      `bin/install-user.sh` links two services and enables their persistent
      timers: `{{NAME}}-src.timer` and `{{NAME}}-archive.timer`. This schedule
      is standing approval for deletion: only the service invocations pass
      --apply automatically. Reactivating a timer can promptly catch up missed
      calendar events; a first installation starts its future schedule.
      No linger is enabled. Disable timers with
      `systemctl --user disable --now {{NAME}}-src.timer {{NAME}}-archive.timer`.

      Both sweeps take a shared blocking flock (`{{CARGO_SWEEP_LOCK}}`);
      overlapping runs wait and execute in turn, including persistent catch-up
      after login. Lock errors fail rather than silently skipping a schedule.
      This coordinates sweeps only, NOT active Cargo builds.
      Run previews before enabling timers
      and avoid building during sweeps. Execution uses absolute mise from the
      home directory to supply its configured cargo/rustup environment for
      metadata. MISE_AUTO_INSTALL=false and MISE_EXEC_AUTO_INSTALL=false disable
      mise tool installation; exec --no-deps also disables automatic dependency
      preparation. A preflight `mise which cargo --tool rust` requires an
      installed mise-selected Cargo, passed via absolute CARGO to metadata:
      there is no ambient/system Cargo fallback. Rustup proxy paths retain the
      cargo basename rather than resolving their symlink to rustup.
      RUSTUP_AUTO_INSTALL=0 disables missing-toolchain installation with
      rustup >=1.28.1 (required). Install the selected toolchain ahead of time.
      These controls are NOT a network sandbox. Timers do not adopt per-project
      mise configs; metadata stays in HOME, and mise's global RUSTUP_TOOLCHAIN
      can override project rust-toolchain files.

      Upstream limitations: age uses access time (filesystem atime policies
      matter), not a workspace's last build. Recursive manifest discovery uses
      Cargo metadata target directories, including shared/external paths:
      root selection is NOT a deletion boundary. Incremental/examples are
      excluded. Hashed artifacts can include dependencies/build outputs used
      by symlinked binaries; un-hashed final binaries generally remain, but
      symlinks are not protection. There is no active-build lock and no support
      here for nightly experimental build-dir. A green status or successful
      sweep does not prove complete reclamation or safe concurrent building.

      Inspect `bin/status.sh`, `systemctl --user list-timers`, and
      `journalctl --user -u {{NAME}}-src.service -u {{NAME}}-archive.service`.
      References: [compfuzor Rust storage](/doc/rust-storage/README.md),
      [cargo-sweep CLI](https://github.com/holmgr/cargo-sweep/blob/v0.8.0/src/cli.rs),
      [discovery](https://github.com/holmgr/cargo-sweep/blob/v0.8.0/src/main.rs),
      [artifact matching](https://github.com/holmgr/cargo-sweep/blob/v0.8.0/src/fingerprint.rs),
      [mise cargo backend](https://mise.jdx.dev/dev-tools/backends/cargo.html),
      [rustup environment](https://rust-lang.github.io/rustup/environment-variables.html),
      [rustup prerequisite](https://github.com/rust-lang/rustup/blob/1.28.2/CHANGELOG.md#L23-L28),
      [cargo_metadata CARGO selection](https://docs.rs/cargo_metadata/0.9.1/src/cargo_metadata/lib.rs.html).

    SYSTEMD_ROOTS: [srcService, srcTimer, archiveService, archiveTimer]
    srcService:
      SYSTEMD_SERVICE: "{{NAME}}-src"
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        Description: Rust src artifacts older than {{CARGO_SWEEP_SRC_DAYS}} days
      SYSTEMD_SERVICES:
        Type: oneshot
        Restart: false
        RestartSec: false
        EnvironmentFile: false
        WorkingDirectory: '%h'
        ExecStart: "{{ (BINS_DIR ~ '/sweep.sh') | replace('%', '%%') | replace('$', '$$') | to_json }} src --apply"
      SYSTEMD_INSTALLS:
        WantedBy: ''
    srcTimer:
      SYSTEMD_TIMER: "{{NAME}}-src"
      SYSTEMD_UNITS:
        Description: Twice-weekly Rust src artifact sweep
      SYSTEMD_TIMERS:
        OnCalendar: "{{CARGO_SWEEP_SRC_CALENDAR}}"
        Persistent: true
        Unit: "{{NAME}}-src.service"
      SYSTEMD_INSTALLS:
        WantedBy: timers.target
    archiveService:
      SYSTEMD_SERVICE: "{{NAME}}-archive"
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        Description: Rust archive artifacts older than {{CARGO_SWEEP_ARCHIVE_DAYS}} days
      SYSTEMD_SERVICES:
        Type: oneshot
        Restart: false
        RestartSec: false
        EnvironmentFile: false
        WorkingDirectory: '%h'
        ExecStart: "{{ (BINS_DIR ~ '/sweep.sh') | replace('%', '%%') | replace('$', '$$') | to_json }} archive --apply"
      SYSTEMD_INSTALLS:
        WantedBy: ''
    archiveTimer:
      SYSTEMD_TIMER: "{{NAME}}-archive"
      SYSTEMD_UNITS:
        Description: Monthly Rust archive artifact sweep
      SYSTEMD_TIMERS:
        OnCalendar: "{{CARGO_SWEEP_ARCHIVE_CALENDAR}}"
        Persistent: true
        Unit: "{{NAME}}-archive.service"
      SYSTEMD_INSTALLS:
        WantedBy: timers.target

    BINS:
      - name: build-cargo-sweep.sh
        src: ../rust-storage/build-mise-tool.sh
        deployment_rooted: true
        env: false
        basedir: false
        phase: packages
        tool: "{{CARGO_SWEEP_TOOL}}"
        executable: cargo-sweep
      - name: sweep.sh
        src: ../rust-storage/sweep.sh
        helpers: false
      - name: status-cargo-sweep.sh
        basedir: false
        exec: |
          test -x {{ (BINS_DIR ~ '/cargo-sweep') | quote }}
          test -d {{ CARGO_SWEEP_SRC_ROOT | quote }}
          test -d {{ CARGO_SWEEP_ARCHIVE_ROOT | quote }}
          systemctl --user is-active {{ (NAME ~ '-src.timer') | quote }} {{ (NAME ~ '-archive.timer') | quote }}
          results=$(systemctl --user show --property=Result --value {{ (NAME ~ '-src.service') | quote }} {{ (NAME ~ '-archive.service') | quote }})
          printf '%s\n' "$results"
          if printf '%s\n' "$results" | grep -qvE '^(success)?$'; then exit 1; fi
    STATUSES: [status-cargo-sweep.sh]

  tasks:
    - import_tasks: tasks/compfuzor.includes
