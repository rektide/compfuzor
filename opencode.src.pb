---
- hosts: all
  vars:
    TYPE: opencode
    INSTANCE: git
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
    # Deployment uses the locally composed jj workspace. The remote working
    # bookmark is only a snapshot and may lag the accepted local composition.
    OPENCODE_WORKING_DIR: "{{ ansible_user_dir }}/src/opencode-working"
    # origin's rolling 'latest' tag drifts from the local fossil; allow clobber.
    #GIT_FORCE: True
    PKGS:
      - binutils
    BACKUP_TARGET: /mnt/fu/backup/opencode-2026-5
    PASSWORDS_DIR: "{{ansible_user_dir}}/.config/opencode/secrets"
    PASSWORDS:
      - name: OPENCODE_PASSWORD
        format: "python3 -c 'import secrets; print(secrets.token_urlsafe(32))'"
        per_host: true
        file: true
    ENV:
      OPENCODE_PRINT_LOGS: 1
      OPENCODE_LOG_LEVEL: INFO
      OPENCODE_SERVER_HOSTNAME: 0.0.0.0
      OPENCODE_SERVER_PORT: 49373
      OPENCODE_SERVER_URL: http://127.0.0.1:49373
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
      SYSTEMD_SERVICE: opencode
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
        SyslogIdentifier: opencode
      SYSTEMD_INSTALLS:
        WantedBy: default.target
    opencodeCleanupService:
      SYSTEMD_SERVICE: opencode-cleanup
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
      SYSTEMD_TIMER: opencode-cleanup
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
        unit: opencode.service
        manager: user
        expected:
          WATCHMAN_SOCK: "{{WATCHMAN_CANONICAL_SOCKET_ABS}}"
      - name: opencode-executable
        check: exe-current
        unit: opencode.service
        manager: user
        expected: "{{GLOBAL_BINS_DIR}}/opencode2"
    ZIM_ENV:
      - OPENCODE_SERVER_URL
      - OPENCODE_PASSWORD_FILE
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

      The persisted 43-character password lives at `${OPENCODE_PASSWORD_FILE}`
      with mode 0600. systemd copies it into a read-only runtime credential;
      `serve.sh` exports it only to the server process. The ZIM module reads the
      same file once in each new shell and exports `OPENCODE_PASSWORD` for
      clients. The secret is never copied into `env`, `env.export`, a unit file,
      or a generated ZIM fragment.

      ## Operations

          systemctl --user status opencode.service
          {{DIR}}/bin/restart.sh
          journalctl --user -u opencode.service -f
          systemctl --user show opencode.service \
            -p ActiveState -p SubState -p MainPID -p NRestarts \
            -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec -p TasksCurrent
          opencode2 api get /api/health
          opencode2 api get /api/server
          {{DIR}}/bin/status.sh
          opencode-status-ok

      `restart.sh` is the managed-service restart path. It reloads systemd when
      needed, restarts only `opencode.service`, waits for `/api/health`, and
      verifies that the new server inherited the canonical Watchman socket.
      It never touches standalone OpenCode panes.

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

      `opencode-last` selects the newest executable dated client snapshot from
      `/usr/local/bin/opencode-<datestamp>` and runs it through the same
      argument-vector-aware routing. `opencode-last list` lists clients
      newest-first.

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
      `systemctl --user restart opencode.service`.

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
          ln -sfv $(pwd)/packages/cli/dist/cli-linux-x64/bin/opencode2 $GLOBAL_BINS_DIR/
          ln -sfv $(pwd)/packages/cli/dist/cli-node-linux-x64/bin/opencode2-node $GLOBAL_BINS_DIR/
      - name: install-user.sh
        basedir: False
        content: |
          dir={{DIR}}
          mkdir -p ~/.local/share/opencode/log

          [ -n "$TARGET" ] || TARGET="$HOME/.config/opencode"
          mkdir -p $(dirname $TARGET)
          ln -sv ${dir}/etc $TARGET/
      - name: opencode-live
        basedir: False
        global: True
        content: |
          # note/beware that we also are pulling in env.exports
          exec bun run --cwd "{{DIR}}" dev $(pwd)
      # TODO: compfuzor helpers for installing content, automate this in install-user
      - name: serve.sh
        basedir: False
      - name: restart.sh
        basedir: False
        content: |
          set -eu
          _unit="${OPENCODE_UNIT:-opencode.service}"
          _url="${OPENCODE_SERVER_URL:-http://127.0.0.1:49373}"
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
      # Stable launcher for the newest immutable dated client snapshot.
      - name: opencode-last
        basedir: False
        raw: True
        global: True
      # status.sh reporter AND standalone global command: `global` as a string
      # renames the link, so it lands in GLOBAL_BINS_DIR as opencode-status-ok
      # while bin/status.sh still runs it under its bin/ name. Standalone-safe:
      # every path it needs comes from env (OPENCODE_*), never the wrapper.
      - name: status-opencode-ok.sh
        basedir: False
        global: opencode-status-ok
      - name: backup.sh
        basedir: False
  tasks:
    - import_tasks: tasks/compfuzor.includes
