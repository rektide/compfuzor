---
- hosts: all
  # Port contract shared with opencode-bus-proxy.src.pb: both playbooks load
  # this one input, so the primary port, the proxy listen port, and the
    # native published proxy URL interpolate from a single authority.
  vars_files:
    - vars/opencode.yaml
  vars:
    TYPE: opencode
    # INSTANCE selects the deployment variant. `git` is the primary instance:
    # it owns the un-suffixed surface (opencode.service, /usr/local/bin/
    # opencode, the ~/.config/opencode link, and the interactive
    # client-env ZIM module). Run any other instance side by side
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
    # Global client links: opencode (primary) / opencode-<INSTANCE>.
    OPENCODE_CLIENT: "opencode{{OPENCODE_SUFFIX}}"
    OPENCODE_CLIENT_NODE: "opencode2-node{{OPENCODE_SUFFIX}}"
    # Secondary instances bind loopback only; the primary keeps its wildcard
    # bind for LAN compatibility. Override per run with
    # -e OPENCODE_SERVER_HOSTNAME=<addr>.
    OPENCODE_SERVER_HOSTNAME: "{{ '0.0.0.0' if OPENCODE_PRIMARY else '127.0.0.1' }}"
    # Secondary instances have no port default: pick an explicit distinct one
    # (-e OPENCODE_SERVER_PORT=<port>) or the guard task fails the run.
    # The primary default is OPENCODE_PRIMARY_PORT from vars/opencode.yaml —
    # the same input the bus proxy dials and the guard reserves. 49374 is
    # the stock upstream managed service.
    OPENCODE_SERVER_PORT: "{{ OPENCODE_PRIMARY_PORT if OPENCODE_PRIMARY else None }}"
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
    PASSWORDS_DIR: "{{ OPENCODE_PRIMARY_PASSWORDS_DIR if OPENCODE_PRIMARY else ansible_user_dir ~ '/.config/opencode' ~ OPENCODE_SUFFIX ~ '/secrets' }}"
    PASSWORDS:
      - name: OPENCODE_PASSWORD
        format: "python3 -c 'import secrets; print(secrets.token_urlsafe(32))'"
        per_host: true
        # Never persisted at render: credential.sh owns the source at install
        # time (through the ~/.config/opencode link). Render-time persistence
        # pre-created the config dir and blocked that link on fresh accounts.
        file: false
    ENV:
      OPENCODE_PRINT_LOGS: 1
      OPENCODE_LOG_LEVEL: INFO
      OPENCODE_SERVER_HOSTNAME: "{{OPENCODE_SERVER_HOSTNAME}}"
      OPENCODE_SERVER_PORT: "{{OPENCODE_SERVER_PORT}}"
      OPENCODE_SERVER_URL: "{{OPENCODE_SERVER_URL}}"
      OPENCODE_PASSWORD_FILE: "{{PASSWORDS_DIR}}/OPENCODE_PASSWORD"
      OPENCODE_DISABLE_AUTOUPDATE: 1
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
      # FFF search-index event source. "shared" (opt-in; default "native")
      # stops FFF from installing its own per-directory inotify watcher and
      # feeds its index incrementally from the same shared watcher feed
      # OPENCODE_WATCHER_BACKEND selects — FFF's own native pipeline still
      # applies every batch (ignore rules, frecency, ranking, git status).
      # Inert on stock upstream builds: the env var is unrecognized there
      # and native FFF watching continues unchanged. Needs the composed
      # workspace's external-ingestion FFF artifacts (vendored under
      # vendor/fff, incl. a Linux library requiring glibc >= 2.38); with a
      # stock or unloadable binary, or after terminal feed loss, search
      # degrades to the ripgrep fallback for that location with a journal
      # warning — it never re-installs the native watcher mid-flight.
      # Applies on the next unit restart.
      OPENCODE_FFF_WATCH: shared
      # Location activity TTL: inert on stock upstream; the composed working
      # workspace reads it. 8h keeps location service stacks warm across a
      # working day while still bounding memory (stock default: 60m).
      OPENCODE_LOCATION_CACHE_TTL: "8 hours"
      # Deployment source of the managed global links; status-opencode-ok.sh
      # reads it to flag links drifting out of the composed workspace. Exported
      # for shells without the ZIM client-env module too (never contains the secret).
      OPENCODE_WORKING_DIR: "{{OPENCODE_WORKING_DIR}}"
      # Native server-reg publisher default, NOT a client-shell wrapper.
      # Empty unless deliberately enabled; secondary launchers stay direct.
      # Older publishers ignore it: select daemon stomp for that transition.
      OPENCODE_PROXY_URL: "{{ 'http://127.0.0.1:' ~ OPENCODE_BUS_PROXY_PORT if OPENCODE_PRIMARY and OPENCODE_BUS_PROXY_DISCOVERY|bool else '' }}"
      OPENCODE_SERVICE_METADATA: "{{ 'true' if OPENCODE_DISCOVERY_METADATA|bool else 'false' }}"
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
        # Literal serve arguments, no wrapper. hostname/port are per-instance
        # render-time constants; --publish claims the channel's single
        # local-discovery registration slot as operator-owned (mode:"server"
        # in service-local.json). Successful binding is the ownership test;
        # the publisher replaces a prior valid record, even a live one on
        # another port. Secondaries omit
        # --publish: the slot is primary-owned, and their clients route via
        # the instance launcher's prepended --server. CORS origins are
        # host-dynamic and deliberately not here: with no --cors flags the
        # server falls back to the config `cors` array maintained by
        # bin/config-cors.sh.
        #
        # Credential: LoadCredential= copies the 0600 password to
        # /run/user/<uid>/credentials/<unit>/ on tmpfs at each start, and the
        # second EnvironmentFile= ({{ETC}}/env-credential, later files win)
        # repoints OPENCODE_PASSWORD_FILE at that copy for the server alone —
        # the binary's existing env-pointer support reads it, 100% env, no
        # --password-file flag. ExecStartPre asserts the pointer against
        # $CREDENTIALS_DIRECTORY (exported to every unit process): a path
        # layout drift fails the boot loudly instead of silently booting an
        # ephemeral password. Requires a binary with env-pointer support.
        ExecStart: "{{OPENCODE_GLOBAL_BINS}}/{{OPENCODE_CLIENT}} serve --hostname {{OPENCODE_SERVER_HOSTNAME}} --port {{OPENCODE_SERVER_PORT}}{{ ' --publish' if OPENCODE_PRIMARY else '' }}"
        # Env: the unit loads ONLY the unit-scoped {{ETC}}/env-service — the
        # runtime keys this deployment declares in ENV/ENV_PRIO/ENV_LIST — and
        # deliberately NOT {{DIR}}/env. The deployment env file begins with
        # the identity header (DIR/NAME/TYPE/INSTANCE/REPO/REPO_DIR/BUILD_DIR/
        # GLOBAL_BINS_DIR) plus compfuzor-contributed keys; loading it exported
        # all of that into the server and every child process (agent sessions,
        # tool shells, playbook runs, materialized bins), where bins'
        # inherited-$DIR deference let this deployment masquerade as another.
        # Bins keep reading {{DIR}}/env and env.export themselves — only the
        # unit's inheritance surface changes. See design/env-pollution/.
        EnvironmentFile:
          - "{{ETC}}/env-service"
          - "{{ETC}}/env-credential"
        LoadCredential: "OPENCODE_PASSWORD:{{PASSWORDS_DIR}}/OPENCODE_PASSWORD"
        ExecStartPre: /bin/sh -c 'test "${OPENCODE_PASSWORD_FILE}" = "${CREDENTIALS_DIRECTORY}/OPENCODE_PASSWORD"'
        WorkingDirectory: "%h"
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
      SYSTEMD_SERVICE: "{{OPENCODE_UNIT}}-cleanup-tmp"
      # The timer activates this unit; installing it must only link the file.
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        Description: Clean inactive OpenCode native-library artifacts
        Documentation: https://github.com/anomalyco/opencode
      SYSTEMD_SERVICES:
        Type: oneshot
        ExecStart: "{{DIR}}/bin/cleanup-tmp.sh --apply --min-age 0s"
        # Do not inherit daemon defaults or the server's environment.
        EnvironmentFile: false
        Restart: false
        RestartSec: false
      SYSTEMD_INSTALLS:
        WantedBy: false
    opencodeCleanupTimer:
      SYSTEMD_TIMER: "{{OPENCODE_UNIT}}-cleanup-tmp"
      SYSTEMD_UNITS:
        Description: Clean inactive OpenCode native-library artifacts every eight hours
        Documentation: https://github.com/anomalyco/opencode
      SYSTEMD_TIMERS:
        OnCalendar: "*-*-* 00/8:00:00"
        Persistent: true
        Unit: opencode-cleanup-tmp.service
      SYSTEMD_INSTALLS:
        WantedBy: timers.target
    # status.sh reporters (prepended before the config/links contributors):
    # status-cleanup.sh dry-runs cleanup-tmp.sh with the timer's eligibility window
    # plus the timer's own unit state; status-opencode-ok.sh checks the
    # invoking shell against the managed deployment and is also globally
    # linked as opencode-status-ok for quick checks from shells without ZIM env.
    STATUSES:
      - name: credential.sh
        args: [status]
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
      # FFF search-feed opt-in must reach the running server's environ;
      # a stale env file (unit not restarted after a playbook run) fails
      # here instead of silently serving native-watch FFF.
      - name: opencode-fff-env
        check: mainpid-env
        unit: "{{OPENCODE_UNIT}}.service"
        manager: user
        expected:
          OPENCODE_FFF_WATCH: shared
      # Credential view of the running server: systemd's LoadCredential
      # tmpfs dir plus the unit-only pointer override that directs the
      # binary at the copy (see {{ETC}}/env-credential).
      - name: opencode-credential-env
        check: mainpid-env
        unit: "{{OPENCODE_UNIT}}.service"
        manager: user
        expected:
          CREDENTIALS_DIRECTORY: "/run/user/{{ ansible_user_uid }}/credentials/{{OPENCODE_UNIT}}.service"
          OPENCODE_PASSWORD_FILE: "/run/user/{{ ansible_user_uid }}/credentials/{{OPENCODE_UNIT}}.service/OPENCODE_PASSWORD"
      - name: opencode-executable
        check: exe-current
        unit: "{{OPENCODE_UNIT}}.service"
        manager: user
        expected: "{{GLOBAL_BINS_DIR}}/{{OPENCODE_CLIENT}}"
    # Only the primary instance imports the interactive client environment
    # module; secondary instances get the same module through their own launcher.
    # |bool keeps the bypass a native boolean (a rendered "False" string would
    # read truthy).
    ZIM_BYPASS: "{{ (not OPENCODE_PRIMARY)|bool }}"
    ZIM_ENV_PHASE: 54
    ZIM_ENV:
      - OPENCODE_SERVER_URL
      - OPENCODE_SERVER_PORT
      - OPENCODE_PASSWORD_FILE
    ZIM_MODULES:
      # Reuse the existing ZIM module identity so its active fragment and init
      # file are updated in place from the old array module to scalar env args.
      - name: opencode-client-args
        source: opencode-client-env.zsh
        phase: 55
        comment: Export the client credential.
    README: |
      # Operator-managed OpenCode V2 server

      `opencode.service` runs plain foreground `opencode serve` on
      `${OPENCODE_SERVER_HOSTNAME}:${OPENCODE_SERVER_PORT}`. It deliberately
      does not use `--service`: with `--publish` among the unit's literal
      serve arguments the server writes an operator-owned `mode:"server"`
      registration into the channel's discovery file
      (service-local.json), but OpenCode still
      performs no incumbent election or self-eviction, never manages this
      process, and refuses to replace or stop it from the client side.
      Lifecycle authority belongs only to the systemd user unit.

      ## Instances

      This deployment is instance-scoped. `INSTANCE=git` (the default) is the
      primary instance and keeps the historical unsuffixed surface: unit
      `opencode.service` / `opencode-cleanup-tmp.timer`, global links `opencode`
      and `opencode2-node` (plus `opencode-status-ok`, `opencode-last`,
      `opencode-live`, `opencode-restart-clients`), the `~/.config/opencode`
      symlink, the interactive
      `opencode` client-env ZIM module, port {{OPENCODE_PRIMARY_PORT}}, wildcard bind, and
      the server's default database.

      Any other instance runs side by side with explicit isolation:

          ansible-playbook -i 'localhost,' -c local opencode.src.pb \
            -e INSTANCE=dev -e OPENCODE_SERVER_PORT=49375

      A secondary instance names everything after itself — deployment
      `/usr/local/src/opencode-<INSTANCE>` (checkout via `GIT_VERSION`, build
      from `~/src/opencode-working-<INSTANCE>`), config `/etc/opt/opencode-<INSTANCE>`,
      credential `~/.config/opencode-<INSTANCE>/secrets/OPENCODE_PASSWORD`,
      units `opencode-<INSTANCE>.service` / `opencode-<INSTANCE>-cleanup-tmp.timer`,
      client links `opencode-<INSTANCE>` / `opencode2-node-<INSTANCE>` — and
      its clients enter through one global launcher:

          opencode-<INSTANCE> [args...]     # e.g. opencode-dev api get /api/info

      The launcher sources the instance env and client-env module and
      prepends `--server <instance URL>` to your arguments (an explicit
      `--server` or `--standalone` in your own arguments suppresses the
      prepend). It never
      manages the server's lifecycle; that stays
      with `systemctl --user` and the instance's own `bin/restart.sh`.

      Isolation defaults for secondaries are deliberate:

      - An explicit distinct `OPENCODE_SERVER_PORT` is required (the run fails
        without one); {{OPENCODE_PRIMARY_PORT}} is the primary, {{OPENCODE_BUS_PROXY_PORT}}
        the bus proxy, and 49374 the stock upstream managed service.
      - The bind defaults to `127.0.0.1`, not the primary's wildcard. Expose a
        secondary deliberately with `-e OPENCODE_SERVER_HOSTNAME=<addr>` and
        the same trust/funnel considerations as the primary's wildcard notes
        below.
      - No `--publish`: the channel's discovery slot is single and
        primary-owned. Instance clients route through the launcher's
        prepended `--server`, never through discovery.
      - The database defaults to `opencode-<INSTANCE>.db` under
        `~/.local/share/opencode/`, separate from every other instance.
       - No ZIM modules are emitted and no `~/.config/opencode` link is made;
         the instance launcher reads its own config through
         `OPENCODE_CONFIG_DIR=/etc/opt/opencode-<INSTANCE>`.

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

      The persisted 43-character password lives at
      `{{PASSWORDS_DIR}}/OPENCODE_PASSWORD` with mode 0600 — one source,
      two views. Clients get the stable home-file pointer: the
      `OPENCODE_PASSWORD_FILE` ENV key rides env.export, and the ZIM module
      reads that file once in each new shell and exports
      `OPENCODE_PASSWORD`. The secret value never appears in any
      environment, env file, unit file, or generated ZIM fragment. The
      server gets systemd's copy: `LoadCredential=` snapshots the file to
      `/run/user/<uid>/credentials/{{OPENCODE_UNIT}}.service/` on tmpfs at
      each start (0400, gone when the unit stops), and the unit's second
      EnvironmentFile (`{{ETC}}/env-credential`, nothing else in it;
      later files win) repoints `OPENCODE_PASSWORD_FILE` at that copy for
      the server alone — the same env-pointer support the binary already
      has, no `--password-file` flag. An `ExecStartPre` assertion compares
      the pointer against `$CREDENTIALS_DIRECTORY` — which systemd exports
      to every unit process — so a credentials-path layout drift fails the
      boot loudly instead of silently booting an ephemeral password. **Deploy ordering**: this route requires a
      binary with `OPENCODE_PASSWORD_FILE` env-pointer support (composed in
      the working workspace since 2026-09); restarting the unit onto an
      older binary boots the server with an ephemeral random password.

      `bin/credential.sh ensure` provisions or secures this account's source
      without rotating an existing password; `bin/credential.sh status` checks
      it without writing. `install-credential-user.sh` exposes ensure in the
      user install lane. Run these as the service account. The primary's
      `OPENCODE_PRIMARY_PASSWORDS_DIR` is shared with the proxy playbook;
      separate accounts get separate source files. Both services use
      `LoadCredential=OPENCODE_PASSWORD:<source>` and receive their own runtime
      copies. After a deliberate source replacement, restart both units so
      their snapshots agree. The tools never print password contents.

      For a separate test account, set both playbooks' shared port inputs,
      for example `OPENCODE_PRIMARY_PORT=49473 OPENCODE_BUS_PROXY_PORT=49472`,
      and use `USERMODE=True` with a loopback origin bind. Its own foreground
      `--publish` initializes its native registration. A proxy using explicit
      `OPENCODE_BUS_PROXY_SERVICE_MODE=stomp` supports an older origin publisher
      until native proxy publication is composed. Client service `disabled`
      must be unset/false: true selects standalone mode and bypasses discovery.

      The user unit gets ordinary runtime settings from its unit-scoped
      generated `EnvironmentFile={{ETC}}/env-service`: the password-file
      pointer, Watchman socket, logging, and the instance's other runtime
      keys — exactly the keys this deployment declares in ENV/ENV_PRIO/
      ENV_LIST. The unit deliberately does NOT load `{{DIR}}/env`: that file
      opens with the deployment identity header (DIR/NAME/TYPE/INSTANCE/
      REPO/REPO_DIR/BUILD_DIR/GLOBAL_BINS_DIR) that bins rely on, and loading
      it made the server — and every child process (agent sessions, tool
      shells, playbook runs) — inherit one deployment's identity, letting
      bins with inherited-$DIR deference quietly source the wrong
      deployment's env. Bins keep reading env/env.export themselves; only
      the unit's inheritance surface changed. The serve arguments
      themselves are literal in the unit — `ExecStart=<binary> serve
      --hostname <addr> --port <port> --publish` (secondaries omit
      `--publish`; their clients route through the instance launcher's
      explicit `--server`) — and CORS origins live in the assembled config
      (see CORS origins below). There is no wrapper: the former
      `serve.sh` word-split adapter existed only because systemd cannot
      split an env var across `ExecStart` argv, and died once nothing
      needed to ride a variable. The credential is fully environment-based
      with two views of one source: the unit reads its password from the
      `OPENCODE_PASSWORD_FILE` pointer that its second EnvironmentFile
      (`{{ETC}}/env-credential`) aims at systemd's `LoadCredential=` tmpfs
      copy, while env.export keeps pointing clients at the stable home
      file — see the password section above for the full story.

      ## Operations

          systemctl --user status {{OPENCODE_UNIT}}.service
          {{DIR}}/bin/restart.sh
          {{DIR}}/bin/restart-clients.sh
          journalctl --user -u {{OPENCODE_UNIT}}.service -f
          systemctl --user show {{OPENCODE_UNIT}}.service \
            -p ActiveState -p SubState -p MainPID -p NRestarts \
            -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec -p TasksCurrent
          {{ 'opencode' if OPENCODE_PRIMARY else 'opencode-' ~ INSTANCE }} api get /api/info
          {{DIR}}/bin/status.sh
          {% if OPENCODE_PRIMARY %}opencode-status-ok{% endif %}

      `restart.sh` is the managed-service restart path. It reloads systemd when
      needed, restarts only `{{OPENCODE_UNIT}}.service`, authenticates to
      `/api/info`, and verifies that the new server inherited the canonical
      Watchman socket.
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
         nothing. The pane's `--publish` discovery registration routes
         the relaunched client to the managed deployment exactly
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
       relaunch through the managed `opencode` command — resume on the current client,
      not the dated binary. Re-running after an interrupted run re-records
      from live processes, so an already-relaunched client may be restarted
      once more before converging.

       Two caveats learned from live testing. First, relaunch rides the
       pane's current client environment: when the running server lags the deployed
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
      WATCHMAN_SOCK, the `OPENCODE_FFF_WATCH=shared` search-feed opt-in, and
      serves the LoadCredential password view:
      `$CREDENTIALS_DIRECTORY` present, `OPENCODE_PASSWORD_FILE` pointing
      at the tmpfs copy), status-exe-current.sh (the MainPID still executes
      the currently deployed opencode inode), plus the config and link drift
      reporters.
      `opencode-status-ok` is the same ok-checker as a global command, so any
      shell — including ones without the ZIM module — can quickly verify three
      things:

      - client: whether the credential is available (exported by the ZIM
        module or readable through the pointer) and the `--publish` discovery
        registration references this deployment's port. The secret itself is
        never written to env or env.export.
      - global: whether the managed links (opencode, opencode2-node) resolve,
        agree on version, and point into OPENCODE_WORKING_DIR rather than a
        stale checkout.
      - shell: what does opencode resolve to on this shell's PATH and whether
        it matches the managed version.

      Exit 0 means this shell is on the managed deployment; exit 1 prints each
      drift line. No network is involved — versions come from `--version`.

      `bin/status-top.sh` (global `opencode-status-top`, primary only) is a
      standalone resident-memory view, not a status.sh reporter: the N
      largest OpenCode client instances by RSS (`-n`, default 8; 0 lists
      all) in a columnar table with PID, RSS and PSS in MB, tmux session
      and window, and the working directory (~-abbreviated). PSS comes
      from smaps_rollup and stays blank where unreadable; RSS across
      instances of one binary overstates unique use, so rank by RSS but
      read PSS for honesty. A trailing `*` on the session marks a location
      recovered from the client's inherited TMUX_PANE rather than live
      ancestry. The origin `serve` process never competes for ranking; it
      is summarized in one footnote line with its own resident size.

      The local `opencode-client-args` ZIM module exports the credential for
      interactive clients. The deployed CLI also reads the
      `OPENCODE_PASSWORD_FILE` pointer itself; the export keeps dated
      snapshot binaries that predate pointer support working. With the
      `--publish` registration active in the same account, clients discover
      the server natively from service-local.json. The proxy contributes its
      contact URL to that record. Neither producer installs OPENCODE_ARGS
      defaults or a shell wrapper; Zim supplies credentials and endpoint
      metadata only. Each account's own server/proxy pair publishes into its
      own native discovery slot.

      Native proxy discovery is opt-in: run both this playbook and
      opencode-bus-proxy.src.pb with `-e OPENCODE_BUS_PROXY_DISCOVERY=true`.
      New server-reg source publishes OPENCODE_PROXY_URL as its contact and
      describes the original service/proxy URLs; the daemon defaults to
      cooperative enrichment. For older publishers, explicitly set
      `-e OPENCODE_BUS_PROXY_SERVICE_MODE=stomp` on the proxy playbook to
      reapply its contact after every origin publication. Metadata is
      default-on (OPENCODE_DISCOVERY_METADATA); routing is never globally
      enabled merely by that default. The proxy Zim endpoint metadata is not
      a client routing mechanism; routing uses the native discovery record.
      Re-source the client-env module in an old shell to remove its former
      proxy wrapper. Source support is not proof that a deployed binary has
      the new flags; composition/build/activation remain operator-gated.

      For standalone mode, pass `--standalone` explicitly.

      `OPENCODE_SERVER_PORT` is the port source of truth;
      `OPENCODE_SERVER_URL` is derived from it.

      `opencode-last` selects the newest executable dated client snapshot from
      `/usr/local/bin/opencode-<datestamp>` and runs it against the managed
      server with an explicit prepended `--server` (discovery is
      build-stamped, and old snapshots predate it; a `--standalone` in your
      arguments suppresses the prepend). `opencode-last list` lists clients
      newest-first.

      ## Dated CLI clients

      Before running `build.sh` to replace the working CLI, preserve the
      currently deployed binary as a no-clobber dated copy:

          stamp=$(date +%Y%m%d%H%M%S)
          snapshot=/usr/local/bin/opencode-$stamp
          test ! -e "$snapshot" && test ! -L "$snapshot" || {
            echo "snapshot exists: $snapshot" >&2; exit 1;
          }
          cp -pL /usr/local/bin/opencode "$snapshot"
          "$snapshot" --version
          cmp -s "$(readlink -f /usr/local/bin/opencode)" "$snapshot" || {
            echo "snapshot mismatch" >&2; exit 1;
          }
          opencode-last list

      The copy is a standalone executable and remains runnable after the build
      replaces its output. `opencode-last` discovers these names dynamically;
      it is not repointed for each snapshot. Keep dated clients until deliberate
      operator cleanup.

      Discovery is build-stamped, so dated snapshots cannot use it:
      `opencode-last` prepends `--server` for them. Run a snapshot
      standalone with an explicit `--standalone`.

      Foreground serve with `--publish` writes an operator-owned
      `mode:"server"` registration into the channel's discovery file —
      `~/.local/state/opencode/service-local.json` under the local channel
      (the stock channel's `service.json` is a separate file and world). That
      file is a single slot, not a directory of records: exactly one
      registration, last successful publisher wins. The current server-reg
      publisher replaces a prior valid record after binding and does not
      self-evict when the slot changes. An unrelated managed service may
      observe that replacement and stop itself; coordinate the deployment
      deliberately rather than treating publication as cross-port fencing.
      While the operator
      registration exists, clients neither spawn nor stop a managed service
      on their own; after the unit is stopped, `opencode service forget`
      clears the stale registration. The registered URL is the bind address
      (`http://0.0.0.0:{{OPENCODE_PRIMARY_PORT}}`); Linux dials 0.0.0.0 as loopback, so local
      clients connect. Discovery also version-gates: the registration
      carries the build stamp, so clients from a different build refuse with
      "the operator owns this deployment" rather than replacing — rebuild
      server and clients together (the restart-clients.sh flow already does).
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

          {{DIR}}/bin/backup.sh --db-only   # fast DB+auth refresh
          {{DIR}}/bin/backup.sh --config    # data + ~/.config/opencode
          {{DIR}}/bin/backup.sh --snapshot  # consistent DB snapshot
          BACKUP_ROOT=user@host:/path {{DIR}}/bin/backup.sh  # ad-hoc target

      ## CORS origins (config-cors.sh)

      The serve unit carries no `--cors` flags. With none given, the
      server falls back to the top-level `cors` array in the assembled
      `etc/opencode.json`, and that array is host-owned:

          {{DIR}}/bin/config-cors.sh              # write etc_d/cors.json + reassemble
          {{DIR}}/bin/config-cors.sh --restart    # ... and restart the unit to apply

      `config-cors.sh` recomputes the origins from live host state —
      `<short hostname>.local` plus every name from `hostname -A`, trailing
      dots stripped, deduplicated in first-seen order, each
      `http://<name>:{{OPENCODE_SERVER_PORT}}` — writes them to the
      host-owned `etc_d/cors.json` fragment (deliberately not a playbook
      ETC_FILES entry: Ansible re-renders never touch it), and reassembles
      the config recipe. Run it whenever hostnames change; new origins
      apply on the next server start. `localhost:`/`127.0.0.1:` origins
      are always allowed by the server and never need listing, and an
      origin whose host matches the request's own Host header is accepted
      without listing.

      The former two-phase env bake (build-env-cors.sh writing
      OPENCODE_SERVER_CORS, build-env-serve-args.sh folding it into a baked
      serve vector) is gone: it had already drifted once in production,
      leaving the running server without any of its origins.

      ## Native-library cleanup

      OpenCode's compiled native dependencies can leave byte-identical hidden
      shared libraries in `/tmp`. The cleanup utility recognizes OpenTUI by its
      ELF SONAME and FFF by its exported API symbols, under their strict Bun
      extraction filename slots. It never traverses `/tmp/opencode` and
      defaults to a dry run with no age delay:

          {{DIR}}/bin/cleanup-tmp.sh
          {{DIR}}/bin/cleanup-tmp.sh --min-age 24h
          {{DIR}}/bin/cleanup-tmp.sh --apply
          {{DIR}}/bin/cleanup-tmp.sh --apply --min-age 24h

      Files mapped or held open by any process are excluded. New dependency
      builds remain eligible as their bytes and sizes change, while unrelated
      randomized shared libraries fail the semantic ELF identity checks. Use
      `--min-age` when an additional retention delay is desired; summaries
      report the count and allocated bytes retained by that delay.

      `opencode-cleanup-tmp.timer` runs the apply form every eight hours.
      `Persistent=true` catches up a missed calendar run when the user manager
      next starts; user lingering keeps that manager available outside login
      sessions on hosts where it is enabled.

          systemctl --user status opencode-cleanup-tmp.timer
          systemctl --user list-timers opencode-cleanup-tmp.timer
          journalctl --user -u opencode-cleanup-tmp.service

      `bin/status.sh` reports cleanup through status-cleanup.sh: it dry-runs
      `cleanup-tmp.sh` with the timer's eligibility window (`--min-age 0s`), so an
      eligible count above zero is drift the next timer run should clear, and
      it also verifies the timer is active and enabled. `--no-timer` skips the
      timer half; `--min-age`/`--tmp-dir` pass through to the dry run.

      ## Portable MCP records

      Existing hand-authored `etc/mcp/*.json` fragments are already wrapped
      for OpenCode and remain untouched. Portable producer `etc/mcp.json`
      records go to a separate input, whose JSON assembler places each record
      under `mcp.servers.<filename stem>` (OpenCode V2):

          {{DIR}}/bin/config-remote.mjs put mcp-portable \
            /usr/local/src/cratedocs-mcp-git/etc/mcp.json cratedocs.json
          {{DIR}}/bin/config-remote.mjs disable mcp-portable cratedocs.json

      The symlink points at the producer's original record. On each assembly,
      `${VAR}` in JSON strings is expanded from that producer's `env.export`
      and the invoking environment; unresolved names fail assembly. Literal
      records do not load or require `env.export`. Legacy variable-bearing
      records require the declared relative env file next to their physical
      source layout; split ETC deployments should prefer literal records or
      OpenCode-native environment references. The producer file is never
      rewritten. For runtime secrets, prefer OpenCode's
      native `{env:VAR}` expression and ensure the server has that variable;
      `${VAR}` expansion writes the value into the assembled config. To avoid
      a stale server configuration, restart the service after changing MCPs.
      Previously deployed `bin/mcp-dropin.ts` and `bin/mcp-dropin-core.ts`
      may remain on disk: Compfuzor does not prune undeclared artifacts. They
      are no longer generated or used; remove them deliberately if desired.

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
    ETC_DIRS:
      - agent
      - etc_d
      - mcp
      - mcp-portable
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
          - glob: mcp-portable/*.json
            name: mcp-portable
            remote: true
            place:
              at: mcp.servers
              as: object
            envsubst:
              file: ../env.export
    ETC_FILES:
      # Unit-scoped service environment file. Contains ONLY the keys this
      # deployment declares for the service (ENV_PRIO + ENV + ENV_LIST names,
      # snapshotted by the OPENCODE_SERVICE_ENV_KEYS task below BEFORE
      # tasks/compfuzor.includes merges compfuzor-contributed identity keys —
      # LINKS_JSON, REPO_DIR, STATUS_DIRS*, APT_INSTALL — into ENV). Values
      # resolve at render time from the same merged ENV that {{DIR}}/env
      # renders, so each line matches the deployment env file exactly.
      # opencode.service loads this file INSTEAD of {{DIR}}/env, so the server
      # and its children no longer inherit the deployment identity header
      # (DIR/NAME/TYPE/...); bins still read env/env.export themselves. Hard
      # (unprefixed) EnvironmentFile reference: this playbook always renders
      # the file, so a missing file fails the unit loudly. See
      # design/env-pollution/ for the full incident and fix scoping.
      - name: env-service
        content: |
          # Unit-scoped service environment for {{NAME}} — deployment identity
          # (DIR, NAME, TYPE, ...) deliberately absent. The full deployment env
          # remains in {{DIR}}/env and {{DIR}}/env.export for bins.
          {% for key in OPENCODE_SERVICE_ENV_KEYS|unique -%}
          {%- set _raw = ENV[key] if key in ENV else lookup('vars', key, default='__CF_ENV_UNSET__') -%}
          {%- if _raw is not none and _raw != '__CF_ENV_UNSET__' %}
          {%- for _val in _raw|normalize(to='list') %}
          {{key|upper}}="{{_val|string}}"
          {% endfor -%}
          {%- endif -%}
          {%- endfor -%}
      - name: env-credential
        content: |
          # Unit-only credential pointer override: the second unit
          # EnvironmentFile= (listed after {{ETC}}/env-service, later files
          # win).
          # systemd's LoadCredential= copies the 0600 password from
          # {{PASSWORDS_DIR}}/OPENCODE_PASSWORD to the unit's tmpfs
          # credentials directory at each start; the server reads that copy
          # through the same env-pointer support, while env.export keeps
          # pointing clients at the stable home file. ExecStartPre asserts
          # this path against $CREDENTIALS_DIRECTORY, so a layout drift
          # fails the boot loudly. This file contains no secret.
          OPENCODE_PASSWORD_FILE=/run/user/{{ ansible_user_uid }}/credentials/{{OPENCODE_UNIT}}.service/OPENCODE_PASSWORD
      - name: base.json
        json:
          "$schema": "https://opencode.ai/config.json"
      # Replace the former active wrapper import in place on ZIM context
      # install. The wrapper is gone; the client-env module exports the
      # credential only and routing rides --publish discovery.
      - name: zim/zimrc/active/55-opencode-service.conf
        content: |
          # Legacy shell helper-wrapper removed.
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
      #- name: agent/mcp-gathering.md
      #  content: |
      #    ---
      #    description: Tool and documentation gathering, review, and comparison
      #    mode: fork
      #    ---

      #    You are looking to find both the best documentation, and, crucially, you want to understand and explain the strengths and weaknesses of what each tool gives you, comparing against one another. Follow these steps:

      #    1. Identify and list which MCP tools might be best for doing research on the libraries or problem we need to work with next. For example, rustdocs, cratedocs, LSP, context7 are all well known MCPs for finding information on code and libraries.
      #    2. After listing tools you want to try, work with each of those tool, one after another, trying to find relevant documentation for the context.
      #    3. After looping through all tools, you will have seen more of the total documentation available. This might suggest other research and exploration you could do. Do a second pass. You don't have to, but if you think there might be a benefit, try new queries that you think could be useful for each tool.
      #    4. Compare how the different sources do. Which sources do you think are the most pertinent? Which have the best examples? Which have are the most comprehensive? Which feel the most on target? How would you characterize the help you got from each tool, when trying to do research about this library or topic?
      #    5. Outline what you have learned.
      #- name: agent/review.md
      #  content: |
      #    ---
      #    description: Reviews code for quality and best practices
      #    mode: subagent
      #    tools:
      #      write: false
      #      edit: false
      #      bash: false
      #    ---

      #    You are in code review mode. Focus on:

      #    - Code quality and best practices
      #    - Potential bugs and edge cases
      #    - Performance implications
      #    - Security considerations

      #    Provide constructive feedback without making direct changes.
      #- name: agent/docs-writer.md
      #  content: |
      #    ---
      #    description: Writes and maintains project documentation
      #    mode: subagent
      #    tools:
      #      bash: false
      #    ---

      #    You are a technical writer. Create clear, comprehensive documentation.

      #    Focus on:

      #    - Clear explanations
      #    - Proper structure
      #    - Code examples
      #    - User-friendly language
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
      - name: credential.sh
        basedir: False
        compose: False
      - name: install-config-user.sh
        # The XDG config entry, alone: ~/.config/opencode becomes the link to
        # this deployment's etc (the password source resolves through it).
        # Standalone-runnable for re-pointing an account without the rest of
        # the user lane.
        scope: [user]
        phase: identity
        basedir: False
        content: |
          {% if OPENCODE_PRIMARY %}
          TARGET="${TARGET:-$HOME/.config/opencode}"
          mkdir -p "$(dirname "$TARGET")"
          if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
            echo "opencode: $TARGET exists and is not a symlink; refusing to replace" >&2
            exit 1
          fi
          ln -svfn "${DIR}/etc" "$TARGET"
          {% else %}
          echo "opencode: secondary instance {{INSTANCE}} has no primary config link" >&2
          exit 0
          {% endif %}
      - name: install-credential-user.sh
        phase: identity
        basedir: False
        content: 'exec {{ (BINS_DIR ~ "/credential.sh") | quote }} ensure'
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
          # opencode/opencode2-node pair as stale. Pin one stamp per run.
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
          ln -sfv $(pwd)/packages/cli/dist/cli-linux-x64/bin/opencode $GLOBAL_BINS_DIR/{{OPENCODE_CLIENT}}
          ln -sfv $(pwd)/packages/cli/dist/cli-node-linux-x64/bin/opencode2-node $GLOBAL_BINS_DIR/{{OPENCODE_CLIENT_NODE}}
      - name: install-user.sh
        basedir: False
        content: |
          dir={{DIR}}
          mkdir -p ~/.local/share/opencode/log
          # Config link, credential, Zim import, and units are each standalone
          # install-*-user.sh targets; this aggregate runs them in order.
      # TODO: compfuzor helpers for installing content, automate this in install-user
      - name: restart.sh
        basedir: False
        content: |
          set -eu
          _unit="${OPENCODE_UNIT:-{{OPENCODE_UNIT}}.service}"
          _url="${OPENCODE_SERVER_URL:-http://127.0.0.1:{{OPENCODE_SERVER_PORT}}}"
          _timeout="${OPENCODE_RESTART_TIMEOUT:-60}"
          _sock="{{WATCHMAN_CANONICAL_SOCKET_ABS}}"
          _password_file="${OPENCODE_PASSWORD_FILE:-$HOME/.config/opencode/secrets/OPENCODE_PASSWORD}"

          _reload="$(systemctl --user show "$_unit" -p NeedDaemonReload --value 2>/dev/null || true)"
          [ "$_reload" = yes ] && systemctl --user daemon-reload
          systemctl --user restart "$_unit"

          _i=0
          while [ "$_i" -lt "$_timeout" ]; do
            if systemctl --user is-active --quiet "$_unit" && [ -r "$_password_file" ]; then
              _cf_restart_xtrace=0
              case $- in *x*) _cf_restart_xtrace=1; set +x ;; esac
              if curl --config <(printf 'user = "opencode:%s"\n' "$(<"$_password_file")") \
                --fail --silent --show-error --max-time 2 "$_url/api/info" >/dev/null 2>&1; then
                _healthy=1
              else
                _healthy=0
              fi
              [ "$_cf_restart_xtrace" -eq 0 ] || set -x
            else
              _healthy=0
            fi
            if [ "$_healthy" -eq 1 ]; then
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
      # --publish discovery registration routes the relaunched client, and
      # the managed server is never touched. Dated-snapshot clients
      # (opencode-<stamp>) relaunch through
      # the managed client rather than their original binary. Global link
      # is primary-only; secondaries keep the local, env-driven bin.
      - name: restart-clients.sh
        basedir: False
        raw: True
        global: "{{ 'opencode-restart-clients' if OPENCODE_PRIMARY else False }}"
      # Host-side CORS regeneration. The serve unit passes no --cors flags,
      # so the server falls back to the config `cors` array; this bin writes
      # the host-owned etc_d/cors.json fragment from live host names and
      # reassembles the config. --restart applies it immediately; a plain
      # run leaves the restart to the operator (a build lane must never
      # restart the live server, which is why this is not a build* leaf).
      - name: config-cors.sh
        basedir: False
      - name: cleanup-tmp.sh
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
      # Standalone-safe: every path it needs comes from env (OPENCODE_*).
      - name: status-opencode-ok.sh
        basedir: False
        global: "{{ 'opencode-status-ok' if OPENCODE_PRIMARY else False }}"
      # Standalone resident-memory view, not a status.sh reporter: top-N
      # OpenCode client instances by RSS with PID, RSS/PSS, tmux
      # session+window, and working directory. Primary links it globally
      # as opencode-status-top (same secondary collision reasoning as
      # status-opencode-ok.sh).
      - name: status-top.sh
        basedir: False
        global: "{{ 'opencode-status-top' if OPENCODE_PRIMARY else False }}"
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
      # defaults (ZIM client-env module, /usr/local/bin snapshots); secondaries keep the
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
      # the instance env and native client-env module. Primary renders the bin
      # but never links it (no OPENCODE_CLIENT_ENV_MODULE in the primary env).
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
          from every other OpenCode endpoint on this host
          ({{OPENCODE_PRIMARY_PORT}} primary server, {{OPENCODE_BUS_PROXY_PORT}}
          bus proxy, 49374 stock upstream managed service).
      when: >-
        not OPENCODE_PRIMARY and (
          OPENCODE_SERVER_PORT is not defined or
          OPENCODE_SERVER_PORT|default('')|string in
          ['', 'None', OPENCODE_PRIMARY_PORT|string, OPENCODE_BUS_PROXY_PORT|string, '49374']
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
    - name: "opencode: secondary instance env keys and client module"
      # Presence-gated keys (OPENCODE_BINARY/OPENCODE_CONFIG_DIR/OPENCODE_DB/
      # OPENCODE_CLIENT_ENV_MODULE) must stay absent for the primary: an empty
      # OPENCODE_DB would be adopted as a real (invalid) path by the server.
      # They ride ENV_PRIO rather than ENV because merging ENV here would
      # render its values (WATCHMAN_SOCK et al.) before vars/common.yaml has
      # loaded; ENV_PRIO overrides nothing for secondaries, it only defines.
      # The client environment module is appended as a plain ETC file because
      # secondaries emit no ZIM modules.
      set_fact:
        ENV_PRIO: "{{ ENV_PRIO|default({}) | combine({
               'OPENCODE_BINARY': OPENCODE_GLOBAL_BINS ~ '/' ~ OPENCODE_CLIENT,
               'OPENCODE_CONFIG_DIR': OPENCODE_INSTANCE_ETC,
               'OPENCODE_DB': OPENCODE_INSTANCE_DB,
              'OPENCODE_CLIENT_ENV_MODULE': OPENCODE_INSTANCE_ETC ~ '/client/client-env.zsh',
             }) }}"
        ETC_FILES: "{{ ETC_FILES + [{'name': 'client/client-env.zsh', 'src': 'opencode-client-env.zsh'}] }}"
      when: not OPENCODE_PRIMARY
    - name: "opencode: snapshot the deployment-declared env keys (unit-scoped service env)"
      # Must run BEFORE tasks/compfuzor.includes: the includes' vars phase
      # merges compfuzor-contributed keys into ENV (LINKS_JSON via
      # gen_links, REPO_DIR via vars_repo, STATUS_DIRS*/APT_INSTALL via
      # common.yaml subsystems) — deployment identity the unit must not
      # inherit. Keys only: common.yaml is not loaded yet, so values could
      # not render here (WATCHMAN_CANONICAL_SOCKET_ABS &c); the env-service
      # ETC file resolves every key from the merged ENV at fs render time,
      # byte-matching {{DIR}}/env. See design/env-pollution/.
      set_fact:
        OPENCODE_SERVICE_ENV_KEYS: >-
          {{ ((ENV_PRIO|default({})).keys()|list)
             + ((ENV.keys()|list) if ENV is mapping else [])
             + (ENV_LIST|default([])|normalize(to='list')) }}
    - import_tasks: tasks/compfuzor.includes
