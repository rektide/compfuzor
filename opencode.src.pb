---
- hosts: all
  vars:
    TYPE: opencode
    # INSTANCE selects the deployment variant. `git` is the primary instance:
    # it owns the un-suffixed surface (opencode.service, /usr/local/bin/
    # opencode2, the ~/.config/opencode link, and the interactive
    # opencode/opencode2 ZIM wrapper). Run any other instance side by side
    # with `-e INSTANCE=<name>`: every generated name, path, port, and
    # credential is instance-suffixed and isolated by default.
    INSTANCE: git
    OPENCODE_PRIMARY_INSTANCE: git
    # |bool keeps this a native boolean: a rendered "False" string would be
    # truthy in every downstream conditional.
    OPENCODE_PRIMARY: "{{ (INSTANCE == OPENCODE_PRIMARY_INSTANCE)|bool }}"
    OPENCODE_SUFFIX: "{{ '' if OPENCODE_PRIMARY else '-' ~ INSTANCE }}"
    # systemd unit basename: opencode (primary) / opencode-<INSTANCE>.
    OPENCODE_UNIT: "opencode{{OPENCODE_SUFFIX}}"
    # Global client links: opencode2 (primary) / opencode2-<INSTANCE>.
    OPENCODE_CLIENT: "opencode2{{OPENCODE_SUFFIX}}"
    OPENCODE_CLIENT_NODE: "opencode2-node{{OPENCODE_SUFFIX}}"
    # Secondary instances bind loopback only; the primary keeps its wildcard
    # bind for LAN compatibility. Override per run with
    # -e OPENCODE_SERVER_HOSTNAME=<addr>.
    OPENCODE_SERVER_HOSTNAME: "{{ '0.0.0.0' if OPENCODE_PRIMARY else '127.0.0.1' }}"
    # Secondary instances have no port default: pick an explicit distinct one
    # (-e OPENCODE_SERVER_PORT=<port>) or the guard task fails the run.
    # 49373 is the primary; 49374 is the stock upstream managed service.
    OPENCODE_SERVER_PORT: "{{ 49373 if OPENCODE_PRIMARY else None }}"
    OPENCODE_SERVER_URL: "http://127.0.0.1:{{OPENCODE_SERVER_PORT}}"
    # Secondary deployments build from their own composed working workspace.
    OPENCODE_WORKING_DIR: "{{ ansible_user_dir }}/src/opencode-working{{OPENCODE_SUFFIX}}"
    # Secondary default DB: isolated file under the shared XDG data dir
    # (~/.local/share/opencode/opencode-<INSTANCE>.db). Override deliberately
    # with -e OPENCODE_DB=<path-or-filename> for shared/clone experiments;
    # the semantics and risks are documented in the README below.
    OPENCODE_INSTANCE_DB: "{{ OPENCODE_DB|default('opencode' ~ OPENCODE_SUFFIX ~ '.db', True) }}"
    # vars/common.yaml (GLOBAL_BINS_DIR, ETCS_DIR) loads inside
    # tasks/compfuzor.includes, but the secondary env merge below runs before
    # it; derive the same locations from the lookup defaults instead. Command
    # line overrides (-e GLOBAL_BINS_DIR/-e ETCS_DIR) are visible directly.
    OPENCODE_GLOBAL_BINS: "{{ lookup('vars', 'GLOBAL_BINS_DIR', default='/usr/local/bin') }}"
    OPENCODE_INSTANCE_ETC: "{{ lookup('vars', 'ETCS_DIR', default='/etc/opt') }}/opencode{{OPENCODE_SUFFIX}}"
    BUN: True
    BUN_BINS: False
    NODEJS: True
    NODEJS_BINS: False
    REPO: https://github.com/anomalyco/opencode
    GIT_REMOTES:
      rektide: https://github.com/rektide/opencode
    # jj-style remote bookmark selector; repo_git resolves this as the working
    # branch fetched from the rektide remote while retaining upstream as origin.
    GIT_VERSION: working@rektide
    # origin's rolling 'latest' tag drifts from the local fossil; allow clobber.
    #GIT_FORCE: True
    PKGS:
      - binutils
    # Backup destinations mirrored in order by bin/backup.sh (space-joined
    # into its BACKUP_TARGETS default). Entries are local paths or
    # user@host:/path remote specs (rsync over ssh, btrfs snapshot versioning
    # via ssh). fu is NTFS via fuseblk, bitblaster is CIFS — both mirror
    # without versioning; btrfs targets get per-run readonly snapshots. A
    # missing/unmounted target is skipped with a warning but fails the run
    # overall.
    BACKUP_TARGETS:
      - /mnt/fu/backup/opencode-2026-5
      - /mnt/bitblaster/backup/opencode/
    # The primary stores its credential under ~/.config/opencode/secrets
    # (which is the symlink to the primary ETC dir); secondaries get their
    # own suffixed directory because ~/.config/opencode stays primary-owned.
    PASSWORDS_DIR: "{{ansible_user_dir}}/.config/opencode{{OPENCODE_SUFFIX}}/secrets"
    PASSWORDS:
      - name: OPENCODE_PASSWORD
        format: "python3 -c 'import secrets; print(secrets.token_urlsafe(32))'"
        per_host: true
        file: true
    ENV:
      OPENCODE_PRINT_LOGS: 1
      OPENCODE_LOG_LEVEL: INFO
      OPENCODE_SERVER_HOSTNAME: "{{OPENCODE_SERVER_HOSTNAME}}"
      OPENCODE_SERVER_PORT: "{{OPENCODE_SERVER_PORT}}"
      OPENCODE_SERVER_URL: "{{OPENCODE_SERVER_URL}}"
      OPENCODE_PASSWORD_FILE: "{{PASSWORDS_DIR}}/OPENCODE_PASSWORD"
      OPENCODE_DISABLE_AUTOUPDATE: 1
      # Rendered empty and rewritten in place by bin/build-env-cors.sh, a
      # build.sh compositor leaf: all hostname -A names plus
      # <short hostname>.local, deduped, each http://<name>:<port>.
      # serve.sh expands each into --cors.
      OPENCODE_SERVER_CORS: ""
      # Root-scoped watchman backend; inert until the composed working
      # workspace carries the watchman stack, then opts the service in.
      # 4m command deadline: loaded host, prefer waiting over generation churn.
      OPENCODE_WATCHER_BACKEND: watchman
      # Defaults for bin/backup.ts: the Node bin template supplies the shebang,
      # while backup.ts reads this env.export for BACKUP_TARGETS at runtime.
      BACKUP_TARGETS: "{{ BACKUP_TARGETS|join(' ') }}"
      OPENCODE_WATCHMAN_COMMAND_TIMEOUT_MS: 240000
      # One canonical socket shared by the mutually-exclusive watchman
      # and watchwoman services. Explicit routing prevents the transport from
      # shelling out `watchman get-sockname`, which can auto-spawn a private
      # daemon in this unit's cgroup.
      WATCHMAN_SOCK: "{{WATCHMAN_CANONICAL_SOCKET_ABS}}"
      # Location activity TTL: inert on stock upstream; the composed working
      # workspace reads it. 8h keeps location service stacks warm across a
      # working day while still bounding memory (stock default: 60m).
      OPENCODE_LOCATION_CACHE_TTL: "8 hours"
      # Deployment source of the managed global links; status-opencode-ok.sh
      # reads it to flag links drifting out of the composed workspace. Exported
      # for shells without the wrapper too (never contains the secret).
      OPENCODE_WORKING_DIR: "{{OPENCODE_WORKING_DIR}}"
    # Optional deployment inputs. Define these as Ansible variables to enable
    # OpenCode's native OTLP/HTTP logs and traces without hard-coding a backend.
    ENV_LIST:
      - OTEL_EXPORTER_OTLP_ENDPOINT
      - OTEL_EXPORTER_OTLP_HEADERS
      - OTEL_RESOURCE_ATTRIBUTES
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    SYSTEMD_ROOTS:
      - opencodeService
      - opencodeCleanupService
      - opencodeCleanupTimer
    opencodeService:
      SYSTEMD_SERVICE: "{{OPENCODE_UNIT}}"
      SYSTEMD_UNITS:
        Description: OpenCode V2 operator-managed foreground server
        Documentation: https://opencode.ai/v2/docs/
        Wants: network-online.target
        After: network-online.target
        StartLimitIntervalSec: 60
        StartLimitBurst: 5
      SYSTEMD_SERVICES:
        # OpenCode is an execution environment and needs the user's normal home,
        # projects, tools, and /tmp. Generic filesystem/process sandboxing would
        # silently break its core job, so harden lifecycle rather than access.
        Type: exec
        ExecStart: "{{DIR}}/bin/serve.sh"
        WorkingDirectory: "%h"
        LoadCredential: "OPENCODE_PASSWORD:{{PASSWORDS_DIR}}/OPENCODE_PASSWORD"
        SuccessExitStatus: 130
        Restart: always
        RestartSec: 1
        RestartSteps: 5
        RestartMaxDelaySec: 30
        TimeoutStopSec: 90
        TimeoutStopFailureMode: kill
        KillSignal: SIGTERM
        FinalKillSignal: SIGKILL
        KillMode: mixed
        UMask: "0077"
        # OpenCode is control-plane infrastructure for active agent work. Exclude
        # it from systemd-oomd's user-slice candidates rather than merely ranking
        # it last; kernel OOM kills still fail and restart the whole unit.
        ManagedOOMPreference: omit
        # A value such as -900 would strongly protect against the kernel OOM
        # killer, but an unprivileged user manager cannot lower oom_score_adj
        # below its own inherited value. On this host systemd accepted -900 but
        # the process remained at 100, so leave this disabled rather than imply
        # protection that is not effective. It requires privileged policy on
        # user@.service or moving this workload to a system service.
        # OOMScoreAdjust: -900
        OOMPolicy: stop
        MemoryAccounting: true
        TasksAccounting: true
        IPAccounting: true
        LimitNOFILE: 1048576
        StandardOutput: journal
        StandardError: journal
        SyslogIdentifier: "{{OPENCODE_UNIT}}"
      SYSTEMD_INSTALLS:
        WantedBy: default.target
    opencodeCleanupService:
      SYSTEMD_SERVICE: "{{OPENCODE_UNIT}}-cleanup"
      # The timer activates this unit; installing it must only link the file.
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        Description: Clean inactive OpenCode native-library artifacts
        Documentation: https://github.com/anomalyco/opencode
      SYSTEMD_SERVICES:
        Type: oneshot
        ExecStart: "{{DIR}}/bin/cleanup.sh --apply --min-age 0s"
        # Do not inherit daemon defaults or the server's environment.
        EnvironmentFile: false
        Restart: false
        RestartSec: false
      SYSTEMD_INSTALLS:
        WantedBy: false
    opencodeCleanupTimer:
      SYSTEMD_TIMER: "{{OPENCODE_UNIT}}-cleanup"
      SYSTEMD_UNITS:
        Description: Clean inactive OpenCode native-library artifacts every eight hours
        Documentation: https://github.com/anomalyco/opencode
      SYSTEMD_TIMERS:
        OnCalendar: "*-*-* 00/8:00:00"
        Persistent: true
        Unit: opencode-cleanup.service
      SYSTEMD_INSTALLS:
        WantedBy: timers.target
    # status.sh reporters (prepended before the config/links contributors):
    # status-cleanup.sh dry-runs cleanup.sh with the timer's eligibility window
    # plus the timer's own unit state; status-opencode-ok.sh checks the
    # invoking shell against the managed deployment and is also globally
    # linked as opencode-status-ok for quick checks from wrapper-less shells.
    STATUSES:
      - status-cleanup.sh
      - status-opencode-ok.sh
    # Proc-backed status checks are typed rows. The provider emits one reporter
    # per check kind and batches every matching row into that reporter.
    STATUS_PROC:
      - name: opencode-watchman-env
        check: mainpid-env
        unit: "{{OPENCODE_UNIT}}.service"
        manager: user
        expected:
          WATCHMAN_SOCK: "{{WATCHMAN_CANONICAL_SOCKET_ABS}}"
      - name: opencode-executable
        check: exe-current
        unit: "{{OPENCODE_UNIT}}.service"
        manager: user
        expected: "{{GLOBAL_BINS_DIR}}/{{OPENCODE_CLIENT}}"
    # Only the primary instance promotes connection facts into interactive
    # shells: ZIM modules define the opencode/opencode2 functions and the
    # OPENCODE_ARGS array, so two imported instances would silently fight over
    # the same shell namespace. Secondary instances bypass ZIM entirely; their
    # entrypoint is the opencode-<INSTANCE> launcher instead. |bool keeps the
    # bypass a native boolean (a rendered "False" string would read truthy).
    ZIM_BYPASS: "{{ (not OPENCODE_PRIMARY)|bool }}"
    ZIM_ENV:
      - OPENCODE_SERVER_URL
      - OPENCODE_SERVER_PORT
      - OPENCODE_PASSWORD_FILE
    # Client-only Zsh argv defaults. Keep these out of ENV/env.export so the
    # systemd `serve` process never receives client connection flags.
    ZIM_ARRAYS_NAME: opencode-client-args
    ZIM_ARRAYS_PHASE: tools
    ZIM_ARRAYS:
      OPENCODE_ARGS:
        - --server
        - "{{ OPENCODE_SERVER_URL }}"
    ZIM_MODULES:
      - name: opencode-service
        source: opencode-service.zsh
        phase: tools
        comment: Route both OpenCode command names through the operator-managed V2 server.
    README: |
      # Operator-managed OpenCode V2 server

      `opencode.service` runs plain foreground `opencode2 serve` on
      `${OPENCODE_SERVER_HOSTNAME}:${OPENCODE_SERVER_PORT}`. It deliberately
      does not use `--service`: OpenCode publishes no registration, performs no
      incumbent election or self-eviction, and never manages this process.
      Lifecycle authority belongs only to the systemd user unit.

      ## Instances

      This deployment is instance-scoped. `INSTANCE=git` (the default) is the
      primary instance and keeps the historical unsuffixed surface: unit
      `opencode.service` / `opencode-cleanup.timer`, global links `opencode2`
      and `opencode2-node` (plus `opencode-status-ok`, `opencode-last`,
      `opencode-live`, `opencode-restart-clients`), the `~/.config/opencode`
      symlink, the interactive
      `opencode`/`opencode2` ZIM wrapper, port 49373, wildcard bind, and the
      server's default database.

      Any other instance runs side by side with explicit isolation:

          ansible-playbook -i 'localhost,' -c local opencode.src.pb \
            -e INSTANCE=dev -e OPENCODE_SERVER_PORT=49375

      A secondary instance names everything after itself — deployment
      `/usr/local/src/opencode-<INSTANCE>` (checkout via `GIT_VERSION`, build
      from `~/src/opencode-working-<INSTANCE>`), config `/etc/opt/opencode-<INSTANCE>`,
      credential `~/.config/opencode-<INSTANCE>/secrets/OPENCODE_PASSWORD`,
      units `opencode-<INSTANCE>.service` / `opencode-<INSTANCE>-cleanup.timer`,
      client links `opencode2-<INSTANCE>` / `opencode2-node-<INSTANCE>` — and
      its clients enter through one global launcher:

          opencode-<INSTANCE> [args...]     # e.g. opencode-dev api get /api/health

      The launcher sources the instance env, so it routes through the same
      boundary-aware `--server` injection as the primary's shell wrapper, with
      `--server`/`--standalone` and administrative commands still passing
      through unchanged. It never manages the server's lifecycle; that stays
      with `systemctl --user` and the instance's own `bin/restart.sh`.

      Isolation defaults for secondaries are deliberate:

      - An explicit distinct `OPENCODE_SERVER_PORT` is required (the run fails
        without one); 49373 is the primary and 49374 the stock upstream
        managed service.
      - The bind defaults to `127.0.0.1`, not the primary's wildcard. Expose a
        secondary deliberately with `-e OPENCODE_SERVER_HOSTNAME=<addr>` and
        the same trust/funnel considerations as the primary's wildcard notes
        below.
      - The database defaults to `opencode-<INSTANCE>.db` under
        `~/.local/share/opencode/`, separate from every other instance.
      - No ZIM modules are emitted and no `~/.config/opencode` link is made:
        two instances must not fight over the interactive `opencode`/`opencode2`
        shell functions or the shared config path. Server and launcher read the
        instance config through `OPENCODE_CONFIG_DIR=/etc/opt/opencode-<INSTANCE>`.

      ### Database sharing

      `-e OPENCODE_DB=<path>` selects the server database explicitly (absolute
      path, or a filename under `~/.local/share/opencode/`). Pointing two live
      servers at one file is an experiment, not a supported mode: beyond SQLite
      write contention, V2 session-execution coordination is process-local, and
      a server starting against a database with suspended execution claims will
      adopt work that may still be running elsewhere. One execution server per
      database is the supported shape; a cloned database carries the clone's
      busy claims and needs a deliberate recovery policy before its server is
      started. The playbook never launches servers for you — units are
      installed but activation is the operator's `systemctl` call.

      What stays shared across instances today: the XDG data/state roots
      (`~/.local/share/opencode`, `~/.local/state/opencode`) hold auth,
      repositories, snapshots, and logs for all instances; the Watchman socket
      is the single canonical user daemon. `backup.sh` mirrors that shared data
      root to every `BACKUP_TARGETS` destination (the fu mount and
      `/mnt/bitblaster/backup/opencode/` by default), so per-instance backup
      targets are an operator choice, not an isolation boundary.

      The persisted 43-character password lives at `${OPENCODE_PASSWORD_FILE}`
      with mode 0600. systemd copies it into a read-only runtime credential;
      `serve.sh` exports it only to the server process. The ZIM module reads the
      same file once in each new shell and exports `OPENCODE_PASSWORD` for
      clients. The secret is never copied into `env`, `env.export`, a unit file,
      or a generated ZIM fragment.

      ## Operations

          systemctl --user status {{OPENCODE_UNIT}}.service
          {{DIR}}/bin/restart.sh
          {{DIR}}/bin/restart-clients.sh
          journalctl --user -u {{OPENCODE_UNIT}}.service -f
          systemctl --user show {{OPENCODE_UNIT}}.service \
            -p ActiveState -p SubState -p MainPID -p NRestarts \
            -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec -p TasksCurrent
          {{ 'opencode2' if OPENCODE_PRIMARY else 'opencode-' ~ INSTANCE }} api get /api/health
          {{ 'opencode2' if OPENCODE_PRIMARY else 'opencode-' ~ INSTANCE }} api get /api/server
          {{DIR}}/bin/status.sh
          {% if OPENCODE_PRIMARY %}opencode-status-ok{% endif %}

      `restart.sh` is the managed-service restart path. It reloads systemd when
      needed, restarts only `{{OPENCODE_UNIT}}.service`, waits for `/api/health`, and
      verifies that the new server inherited the canonical Watchman socket.
      It never touches standalone OpenCode panes.

      `restart-clients.sh` is the client-side counterpart (global command:
      `opencode-restart-clients`, primary instance only). It restarts every
      OpenCode client on the host without touching the server:

      1. **record** — for each live root client process (topmost opencode
         process of a tree, plain TUI argv only), resolve the opencode
         session id with `cotail find-id <pid> --id-only` — the only
         working resolver, since client processes never carry
         `OPENCODE_SESSION_ID` in their environ (that env reaches tool
         shells via the opencode-shell-sessionids plugin, never the TUIs)
         — and its tmux pane by walking the PPid chain to a pane shell,
         then append one TSV row to an in-memory registry at
         `${XDG_RUNTIME_DIR:-/run/user/<uid>}/opencode/clients.tsv`
         (tmpfs: runtime truth, wiped at logout/reboot, never durable
         config).
      2. **kill** — kill the recorded clients (TERM with a 20s grace,
         then KILL), sweep orphaned pane-descendant opencode processes,
         and keep the registry for a later relaunch. The server is not
         touched: this is the window to restart it.
      3. **relaunch** — for each registry entry, wait for its pane's shell
         to resurface and `tmux send-keys` `opencode --session <id>` (no
         `cd`: the pane shell is normally still in the launch directory;
         drift against the recorded cwd is reported, and a cd-prefixed
         form is kept commented in the bin). Reads the registry without
         re-recording — the clients are dead, a fresh scan would find
         nothing. The pane's ZIM wrapper injects `--server`, so the
         relaunched client reattaches to the managed deployment exactly
         like a manual relaunch.
      4. **restart** (default) — one-pass kill + relaunch for client-only
         churn when the server is current and builds match.
         **list** prints the registry with liveness annotations, and
         **clear** forgets it. `-n`/`--dry-run` previews any of these
         without killing or sending.

      Full-restart sequence — clients die first, then the server, then
      the clients come back against the new server:

          {{DIR}}/bin/restart-clients.sh kill
          {{DIR}}/bin/restart.sh
          {{DIR}}/bin/restart-clients.sh relaunch

      Sessions idle longer than `OPENCODE_RESTART_CLIENTS_MAX_IDLE`
      (default `5d`, `0` disables) are not relaunched: the gate reads
      cotail's `timeIdle`/`timeUpdated` for the recorded session and
      leaves stale panes as plain shells.

      Excluded by design: the server unit's MainPID and any `serve` process,
      server-spawned tool shells (not pane descendants), and the script's
      own tree. Clients with no resolvable session id, or whose pane is gone
      or showing another foreground program at relaunch time, are killed but
      left as a plain shell with a warning. Dated-snapshot clients
      (`opencode-<stamp>`, see below) are recorded with their exe but
      relaunch through the managed wrapper — resume on the current client,
      not the dated binary. Re-running after an interrupted run re-records
      from live processes, so an already-relaunched client may be restarted
      once more before converging.

      Two caveats learned from live testing. First, relaunch rides the
      pane's current wrapper: when the running server lags the deployed
      client build (the exe drift `status.sh`'s exe-current reporter
      flags), a one-pass restart reconnects clients to a server they
      cannot talk to — use the kill / `restart.sh` / relaunch sequence
      above so clients come back only after the server is current.
      Second, session resolution is `cotail find-id` (cwd + most recently
      updated session): a freshly launched TUI that never ran a prompt can
      associate with a different recently active session in the same
      directory. The idle gate (above) bounds which sessions come back at
      all; see `OPENCODE_RESTART_CLIENTS_MAX_IDLE` in the bin.

      OpenCode and both watcher daemons use Watchman's XDG-default socket:
      `${XDG_STATE_HOME:-$HOME/.local/state}/watchman/<user>-state/sock`
      (defined once in vars/common.yaml). `watchman.socket` — activating
      `watchwoman.service` through its `watchman.service` alias — and the
      `watchman-facebook.service` fallback conflict with one another, so
      starting either one performs an explicit endpoint handover rather than
      creating a second socket namespace.

      `bin/status.sh` runs the registered reporters: status-cleanup.sh (leaked
      native libraries and the cleanup timer's state), status-opencode-ok.sh
      (below), status-mainpid-env.sh (the live server inherited the canonical
      WATCHMAN_SOCK), status-exe-current.sh (the MainPID still executes the
      currently deployed opencode2 inode), plus the config and link drift
      reporters.
      `opencode-status-ok` is the same ok-checker as a global command, so any
      shell — including ones without the ZIM wrapper — can quickly verify three
      things:

      - wrapper: whether the invoking shell loaded the opencode/opencode2
        wrapper. Shell functions are invisible to child processes, so the check
        reads their footprint: OPENCODE_PASSWORD exported by the ZIM module
        (the secret itself is never written to env or env.export).
      - global: whether the managed links (opencode2, opencode2-node) resolve,
        agree on version, and point into OPENCODE_WORKING_DIR rather than a
        stale checkout.
      - shell: what opencode/opencode2 resolve to on this shell's PATH and
        whether those binaries match the managed version.

      Exit 0 means this shell is on the managed deployment; exit 1 prints each
      drift line. No network is involved — versions come from `--version`.

      The ZIM functions for `opencode` and `opencode2` inject
      `--server ${OPENCODE_SERVER_URL}` for ordinary clients. They never start,
      stop, probe, replace, or reconcile the server. Initial connection failure
      is therefore fast and points back to `systemctl`; an established TUI uses
      OpenCode's existing event-stream reconnection behavior.

      Compfuzor's `opencode-client-args` ZIM array module defines `OPENCODE_ARGS`
      as a Zsh-only array containing `--server` and the configured URL for
      interactive client shells. It is not an exported process environment
      value and is not added to the systemd server environment. The ZIM runner
      inserts those argument tokens at the correct command-parser boundary;
      explicit `--server` and `--standalone` still override the default.
      `opencode-last` clears an inherited scalar `OPENCODE_ARGS`, sources the
      client-only array module, and delegates to the same runner. Native CLI
      environment support for `OPENCODE_ARGS` remains a separate, not-started
      working-set change.

      `OPENCODE_SERVER_PORT` is the port source of truth; `OPENCODE_SERVER_URL`
      and the client `OPENCODE_ARGS` default are derived from it. If the client
      array is missing or empty, the wrapper falls back to
      `--server http://127.0.0.1:${OPENCODE_SERVER_PORT}`.

      `opencode-last` selects the newest executable dated client snapshot from
      `/usr/local/bin/opencode-<datestamp>` and runs it through the same
      argument-vector-aware routing. `opencode-last list` lists clients
      newest-first.

      ## Dated CLI clients

      Before running `build.sh` to replace the working CLI, preserve the
      currently deployed binary as a no-clobber dated copy:

          stamp=$(date +%Y%m%d%H%M%S)
          snapshot=/usr/local/bin/opencode-$stamp
          test ! -e "$snapshot" && test ! -L "$snapshot" || {
            echo "snapshot exists: $snapshot" >&2; exit 1;
          }
          cp -pL /usr/local/bin/opencode2 "$snapshot"
          "$snapshot" --version
          cmp -s "$(readlink -f /usr/local/bin/opencode2)" "$snapshot" || {
            echo "snapshot mismatch" >&2; exit 1;
          }
          opencode-last list

      The copy is a standalone executable and remains runnable after the build
      replaces its output. `opencode-last` discovers these names dynamically;
      it is not repointed for each snapshot. Keep dated clients until deliberate
      operator cleanup.

      `serve`, `service`, an explicit `--server`, and `--standalone` bypass the
      wrapper so the upstream default world remains available as a parallel
      fallback. Current command handlers for `pair`, `plugin list`,
      `mcp list/auth/logout`, `console login`, and `debug config/agents` do not
      honor the global explicit-server path; those commands still target the
      fallback world until the optional upstream consistency patch lands.

      Foreground mode never writes `~/.local/state/opencode/service.json`.
      Existing default-world processes and registrations on port 49374 may
      coexist and share the channel database; concurrent SQLite writers are
      supported but can contend.

      ## Backups

      `bin/backup.sh` mirrors `~/.local/share/opencode/` — the shared data
      root for all instances: auth, DBs, sessions, snapshots, logs — to every
      `BACKUP_TARGETS` destination. Entries are local paths or
      `user@host:/path` remote specs (rsync over ssh; btrfs operations run
      by ssh'ing into the host). Defaults: the fu mount and
      `/mnt/bitblaster/backup/opencode/` (both non-btrfs, so they mirror
      without versioning and say so).

      On btrfs targets the mirror lives in a `<target>/opencode`
      subvolume (bootstrapped on first run) and every successful rsync is
      versioned as a readonly snapshot under `<target>/.snapshots/`,
      pruned to `BACKUP_SNAPSHOT_KEEP` (default 14). Old DB generations
      therefore survive a corrupted live DB. Readonly snapshot deletion
      needs root even with user_subvol_rm_allowed: pruning tries plain
      `btrfs subvolume delete`, then `sudo -n`, then warns — give backup
      hosts a narrow sudoers rule for `btrfs subvolume delete` if you want
      unattended pruning.

      `--snapshot [db ...]` skips the mirror and writes a consistent
      per-DB snapshot to `<target>/consistent-snapshot-<stamp>/` using
      sqlite3 `.backup` (WAL-safe while the server runs) +
      `PRAGMA integrity_check` + SHA256SUMS — works on any filesystem,
      costs a full DB copy per snapshot.

      `bin/backup.ts` is the TypeScript port of the same tool (node
      `parse-args` CLI, deployed through Compfuzor's Node bin template and
      reading this deployment's `env.export` for its `BACKUP_TARGETS`
      default). Behavior and flags match `backup.sh`; retire one once the
      other is proven.

      `bin/mcp-dropin.ts` is also a Node/TypeScript bin: Compfuzor renders
      this instance's MCP remote settings into the entry point, which calls
      `mcp-dropin-core.ts` directly. There is no Bash exec wrapper between
      the two; run it with `[source-dir]` (defaults to the current directory).

          {{DIR}}/bin/backup.sh --db-only   # fast DB+auth refresh
          {{DIR}}/bin/backup.sh --config    # data + ~/.config/opencode
          {{DIR}}/bin/backup.sh --snapshot  # consistent DB snapshot
          BACKUP_ROOT=user@host:/path {{DIR}}/bin/backup.sh  # ad-hoc target

      ## CORS origins

      `bin/build-env-cors.sh` is composed into `build.sh` by the bin
      compositor (its `build*` name groups it there), so every build rewrites
      `OPENCODE_SERVER_CORS` in `env` and `env.export` in place: every name
      from `hostname -A` plus `<short hostname>.local`, deduplicated in
      first-seen order, each as `http://<name>:<port>`, comma-separated. The
      playbook renders the key empty, so an Ansible re-render resets it until
      the next build (or a manual `{{DIR}}/bin/build-env-cors.sh` run).
      `serve.sh` expands each origin into a repeatable `--cors` flag; an empty
      value means no flags. Apply changes with
      `systemctl --user restart {{OPENCODE_UNIT}}.service`.

      ## Native-library cleanup

      OpenCode's compiled native dependencies can leave byte-identical hidden
      shared libraries in `/tmp`. The cleanup utility recognizes OpenTUI by its
      ELF SONAME and FFF by its exported API symbols, under their strict Bun
      extraction filename slots. It never traverses `/tmp/opencode` and
      defaults to a dry run with no age delay:

          {{DIR}}/bin/cleanup.sh
          {{DIR}}/bin/cleanup.sh --min-age 24h
          {{DIR}}/bin/cleanup.sh --apply
          {{DIR}}/bin/cleanup.sh --apply --min-age 24h

      Files mapped or held open by any process are excluded. New dependency
      builds remain eligible as their bytes and sizes change, while unrelated
      randomized shared libraries fail the semantic ELF identity checks. Use
      `--min-age` when an additional retention delay is desired; summaries
      report the count and allocated bytes retained by that delay.

      `opencode-cleanup.timer` runs the apply form every eight hours.
      `Persistent=true` catches up a missed calendar run when the user manager
      next starts; user lingering keeps that manager available outside login
      sessions on hosts where it is enabled.

          systemctl --user status opencode-cleanup.timer
          systemctl --user list-timers opencode-cleanup.timer
          journalctl --user -u opencode-cleanup.service

      `bin/status.sh` reports cleanup through status-cleanup.sh: it dry-runs
      `cleanup.sh` with the timer's eligibility window (`--min-age 0s`), so an
      eligible count above zero is drift the next timer run should clear, and
      it also verifies the timer is active and enabled. `--no-timer` skips the
      timer half; `--min-age`/`--tmp-dir` pass through to the dry run.

      ## Operational notes

      Set `OTEL_EXPORTER_OTLP_ENDPOINT` (and optionally
      `OTEL_EXPORTER_OTLP_HEADERS` / `OTEL_RESOURCE_ATTRIBUTES`) as Ansible
      variables to export logs and traces over OTLP/HTTP. Collector failure does
      not fail OpenCode, so monitor the collector independently.

      The local log under `~/.local/share/opencode/log/` is not rotated by
      OpenCode. Its growth requires an external retention policy. The wildcard
      HTTP bind also exposes Basic Auth without transport encryption; constrain
      it to trusted interfaces/networks or put it behind an encrypted tunnel.

      `ManagedOOMPreference=omit` excludes this unit from systemd-oomd memory
      pressure selection inside the monitored user-manager cgroup. It does not
      override the kernel OOM killer. An unprivileged user manager cannot lower
      `OOMScoreAdjust` below its inherited value; kernel-level priority would
      require a deliberate privileged policy for `user@.service` or a system
      service deployment. `OOMPolicy=stop` keeps an OOM failure coherent, and
      `Restart=always` recovers process exits with bounded backoff.
    MCP_CLIENT:
      remote: mcp
      wrapper: mcp
    ETC_DIRS:
      - agent
      - etc_d
      - mcp
    CONFIGS:
      opencode.json:
        processor: json-deep-merge
        inputs:
          - file: base.json
          - glob: etc_d/*.json
            name: opencode-core
          - glob: mcp/*.json
            name: mcp
            remote: true
    ETC_FILES:
      - name: base.json
        json:
          "$schema": "https://opencode.ai/config.json"
      - name: etc_d/keybind-tabs.json
        json:
          keybinds:
            session_tab_previous: ctrl+h
            session_tab_next: ctrl+l
      - name: etc_d/gsd.json
        json:
          permission:
            read:
              "~/.config/opencode/get-shit-done/*": "allow"
            external_directory:
              "~/.config/opencode/get-shit-done/*": "allow"
      - name: etc_d/permission.json
        json:
          permission:
            "*": "allow"
            external_directory:
              "*": "allow"
            doom_loop: "allow"
      - name: etc_d/openai-codex.json
        json:
          plugin:
            - "opencode-openai-codex-auth"
      - name: etc_d/zai-coding-plan.json
        json:
          provider:
            zai-coding-plan:
              options:
                timeout: 600000
      - name: etc_d/autoupdate.json
        json:
          autoupdate: false
      - name: agent/mcp-gathering.md
        content: |
          ---
          description: Tool and documentation gathering, review, and comparison
          mode: fork
          ---

          You are looking to find both the best documentation, and, crucially, you want to understand and explain the strengths and weaknesses of what each tool gives you, comparing against one another. Follow these steps:

          1. Identify and list which MCP tools might be best for doing research on the libraries or problem we need to work with next. For example, rustdocs, cratedocs, LSP, context7 are all well known MCPs for finding information on code and libraries.
          2. After listing tools you want to try, work with each of those tool, one after another, trying to find relevant documentation for the context.
          3. After looping through all tools, you will have seen more of the total documentation available. This might suggest other research and exploration you could do. Do a second pass. You don't have to, but if you think there might be a benefit, try new queries that you think could be useful for each tool.
          4. Compare how the different sources do. Which sources do you think are the most pertinent? Which have the best examples? Which have are the most comprehensive? Which feel the most on target? How would you characterize the help you got from each tool, when trying to do research about this library or topic?
          5. Outline what you have learned.
      - name: agent/review.md
        content: |
          ---
          description: Reviews code for quality and best practices
          mode: subagent
          tools:
            write: false
            edit: false
            bash: false
          ---

          You are in code review mode. Focus on:

          - Code quality and best practices
          - Potential bugs and edge cases
          - Performance implications
          - Security considerations

          Provide constructive feedback without making direct changes.
      - name: agent/docs-writer.md
        content: |
          ---
          description: Writes and maintains project documentation
          mode: subagent
          tools:
            bash: false
          ---

          You are a technical writer. Create clear, comprehensive documentation.

          Focus on:

          - Clear explanations
          - Proper structure
          - Code examples
          - User-friendly language
      #- name: provider/openrouter.json
      #  json:
      #    provider:
      #      openrouter:
      #        options:
      #          apiKEy: "{env:OPENROUTER_API_KEY}"
    # One static BINS list for every instance: the compfuzor filters read
    # declarations through raw_copy_template_data, so top-level conditional
    # compositions cannot be digested. Instance differences live in
    # field-level templates and rendered content instead (global link names,
    # link targets, unit defaults). Interactive-surface notes: opencode-last
    # and opencode-live keep their bins everywhere (their defaults target the
    # primary deployment; secondaries reach clients through the launcher),
    # but only the primary links them globally.
    BINS:
      - name: build.sh
        basedir: False
        content: |
          cd "{{OPENCODE_WORKING_DIR}}"
          # Baked into the binaries via packages/script. Unset, the build falls
          # back to `git branch --show-current`, which is empty in a jj
          # workspace and would otherwise name the channel after the branch.
          # local keeps service-local.json, port 0xc0df, opencode-local.db,
          # inline sourcemaps, and disables the self-updater.
          export OPENCODE_CHANNEL=local
          # Preview versions stamp YYYYMMDDHHMM per invocation, so separately
          # invoked builds never agree and status-opencode-ok.sh flags the
          # opencode2/opencode2-node pair as stale. Pin one stamp per run.
          export OPENCODE_VERSION="0.0.0-local-$(date -u +%Y%m%d%H%M)"
          bun install --frozen-lockfile
          # build.ts and build-node.ts each wipe their outdir unconditionally;
          # running both against dist/ sequentially erases the first artifact.
          # The node variant builds into a side outdir and merges in after.
          bun run --cwd packages/cli build -- --single --skip-install
          bun run --cwd packages/cli build:node -- --single --skip-install --outdir=dist.node
          mv packages/cli/dist.node/cli-node-* packages/cli/dist/
          rmdir packages/cli/dist.node
      - name: install.sh
        basedir: False
        content: |
          cd "{{OPENCODE_WORKING_DIR}}"
          ln -sfv $(pwd)/packages/cli/dist/cli-linux-x64/bin/opencode2 $GLOBAL_BINS_DIR/{{OPENCODE_CLIENT}}
          ln -sfv $(pwd)/packages/cli/dist/cli-node-linux-x64/bin/opencode2-node $GLOBAL_BINS_DIR/{{OPENCODE_CLIENT_NODE}}
      - name: install-user.sh
        basedir: False
        content: |
          dir={{DIR}}
          mkdir -p ~/.local/share/opencode/log
          {% if OPENCODE_PRIMARY %}
          [ -n "$TARGET" ] || TARGET="$HOME/.config/opencode"
          mkdir -p $(dirname $TARGET)
          ln -sv ${dir}/etc $TARGET/
          {% endif %}
      # TODO: compfuzor helpers for installing content, automate this in install-user
      - name: serve.sh
        basedir: False
      - name: restart.sh
        basedir: False
        content: |
          set -eu
          _unit="${OPENCODE_UNIT:-{{OPENCODE_UNIT}}.service}"
          _url="${OPENCODE_SERVER_URL:-http://127.0.0.1:{{OPENCODE_SERVER_PORT}}}"
          _timeout="${OPENCODE_RESTART_TIMEOUT:-60}"
          _sock="{{WATCHMAN_CANONICAL_SOCKET_ABS}}"

          _reload="$(systemctl --user show "$_unit" -p NeedDaemonReload --value 2>/dev/null || true)"
          [ "$_reload" = yes ] && systemctl --user daemon-reload
          systemctl --user restart "$_unit"

          _i=0
          while [ "$_i" -lt "$_timeout" ]; do
            if systemctl --user is-active --quiet "$_unit" && \
              curl --fail --silent --show-error --max-time 2 "$_url/api/health" >/dev/null 2>&1; then
              _pid="$(systemctl --user show "$_unit" -p MainPID --value)"
              _actual="$(tr '\0' '\n' <"/proc/$_pid/environ" 2>/dev/null | sed -n 's/^WATCHMAN_SOCK=//p' | head -1)"
              [ "$_actual" = "$_sock" ] || {
                echo "restart-opencode: service WATCHMAN_SOCK is '${_actual:-unset}', expected '$_sock'" >&2
                exit 1
              }
              echo "restart-opencode: $_unit healthy (MainPID $_pid, WATCHMAN_SOCK=$_sock)"
              exit 0
            fi
            sleep 1
            _i=$((_i + 1))
          done

          systemctl --user status "$_unit" --no-pager >&2 || true
          echo "restart-opencode: $_unit did not become healthy within ${_timeout}s" >&2
          exit 1
      # Client-side counterpart to restart.sh (raw bin: files/opencode/
      # restart-clients.sh). Records every live client's opencode session id
      # (cotail find-id) and tmux pane into an in-mem tmpfs registry, kills
      # the clients, then relaunches each in its recorded pane via tmux
      # send-keys with `cd <cwd> && opencode --session <id>` — the pane's
      # ZIM wrapper injects --server, and the managed server is never
      # touched. Dated-snapshot clients (opencode-<stamp>) relaunch through
      # the managed wrapper rather than their original binary. Global link
      # is primary-only; secondaries keep the local, env-driven bin.
      - name: restart-clients.sh
        basedir: False
        raw: True
        global: "{{ 'opencode-restart-clients' if OPENCODE_PRIMARY else False }}"
      # Auto-grouped under the build.sh compositor by its build* name; every
      # build.sh run refreshes the origins, no explicit call site required.
      - name: build-env-cors.sh
        basedir: False
      - name: cleanup.sh
        basedir: False
      # status.sh reporter: leaked native libraries + timer state. Local bin
      # only (STATUSES runs it via bin/status.sh).
      - name: status-cleanup.sh
        basedir: False
      # status.sh reporter AND standalone global command — but only for the
      # primary instance: `global` as a string renames the link into
      # GLOBAL_BINS_DIR as opencode-status-ok, and a second deployment would
      # collide on that name. Secondary instances keep the bin locally (env
      # driven, so it checks its own instance) without the global link.
      # Standalone-safe: every path it needs comes from env (OPENCODE_*),
      # never the wrapper.
      - name: status-opencode-ok.sh
        basedir: False
        global: "{{ 'opencode-status-ok' if OPENCODE_PRIMARY else False }}"
      - name: backup.sh
        basedir: False
      # TypeScript port of backup.sh (node:util parse-args CLI). The Node
      # template emits the shebang; backup.ts reads env.export for defaults
      # (BACKUP_TARGETS rides ENV for exactly that).
      - name: backup.ts
        basedir: False
        runtime: node
      # Primary-only interactive surface: the dev-TUI launcher and the dated
      # snapshot runner both target the primary deployment through unsuffixed
      # defaults (ZIM modules, /usr/local/bin snapshots); secondaries keep the
      # local bins but never link them globally.
      - name: opencode-live
        basedir: False
        global: "{{ True if OPENCODE_PRIMARY else False }}"
        content: |
          # note/beware that we also are pulling in env.exports
          exec bun run --cwd "{{DIR}}" dev $(pwd)
      # Stable launcher for the newest immutable dated client snapshot.
      - name: opencode-last
        basedir: False
        raw: True
        global: "{{ True if OPENCODE_PRIMARY else False }}"
      # Secondary entrypoint: linked globally as opencode-<INSTANCE>, sources
      # the instance env, and routes the client through _opencode_run exactly
      # like the primary's ZIM wrapper. Primary renders the bin but never
      # links it (no OPENCODE_SERVICE_MODULE in the primary env).
      - name: opencode-instance
        basedir: False
        raw: True
        global: "{{ 'opencode-' ~ INSTANCE if not OPENCODE_PRIMARY else False }}"
  tasks:
    - name: "opencode: secondary instances require an explicit distinct server port"
      fail:
        msg: >-
          INSTANCE={{INSTANCE}} is a secondary deployment and needs an
          explicit port: rerun with -e OPENCODE_SERVER_PORT=<port>, distinct
          from every other OpenCode server on this host (49373 is the primary
          instance, 49374 the stock upstream managed service).
      when: >-
        not OPENCODE_PRIMARY and (
          OPENCODE_SERVER_PORT is not defined or
          OPENCODE_SERVER_PORT|default('')|string in ['', 'None', '49373', '49374']
        )
    - name: "opencode: note operator-selected database path"
      debug:
        msg: >-
          OPENCODE_DB={{OPENCODE_INSTANCE_DB}} is operator-selected for
          INSTANCE={{INSTANCE}}. One live execution server per database is the
          supported shape: V2 session-execution coordination is process-local,
          and a server starting against a database with suspended execution
          claims will adopt work that may still be running elsewhere. Sharing
          is an explicit experiment, not a supported concurrent mode.
      when: not OPENCODE_PRIMARY and OPENCODE_DB is defined
    - name: "opencode: secondary instance env keys and routing module"
      # Presence-gated keys (OPENCODE_BINARY/OPENCODE_CONFIG_DIR/OPENCODE_DB/
      # OPENCODE_SERVICE_MODULE) must stay absent for the primary: an empty
      # OPENCODE_DB would be adopted as a real (invalid) path by the server.
      # They ride ENV_PRIO rather than ENV because merging ENV here would
      # render its values (WATCHMAN_SOCK et al.) before vars/common.yaml has
      # loaded; ENV_PRIO overrides nothing for secondaries, it only defines.
      # The client routing module is appended as a plain ETC file because
      # secondaries emit no ZIM modules.
      set_fact:
        ENV_PRIO: "{{ ENV_PRIO|default({}) | combine({
               'OPENCODE_BINARY': OPENCODE_GLOBAL_BINS ~ '/' ~ OPENCODE_CLIENT,
               'OPENCODE_CONFIG_DIR': OPENCODE_INSTANCE_ETC,
               'OPENCODE_DB': OPENCODE_INSTANCE_DB,
               'OPENCODE_SERVICE_MODULE': OPENCODE_INSTANCE_ETC ~ '/client/service.zsh',
             }) }}"
        ETC_FILES: "{{ ETC_FILES + [{'name': 'client/service.zsh', 'src': 'opencode-service.zsh'}] }}"
      when: not OPENCODE_PRIMARY
    - import_tasks: tasks/compfuzor.includes
