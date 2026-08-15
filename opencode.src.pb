---
- hosts: all
  vars:
    TYPE: opencode
    INSTANCE: git
    #REPO: https://github.com/anomalyco/opencode
    #GIT_VERSION: v2
    REPO: https://github.com/rektide/opencode
    GIT_VERSION: working
    TOOL_VERSIONS:
      bun: 1
      go: 1
    BACKUP_TARGET: /mnt/fu/backup/opencode-2026-5
    ENV:
      OPENCODE_PRINT_LOGS: 1
      OPENCODE_LOG_LEVEL: INFO
      OPENCODE_SERVICE_HOSTNAME: 0.0.0.0
      OPENCODE_SERVICE_PORT: 49374
      OPENCODE_SERVICE_URL: http://127.0.0.1:49374
    # Optional deployment inputs. Define these as Ansible variables to enable
    # OpenCode's native OTLP/HTTP logs and traces without hard-coding a backend.
    ENV_LIST:
      - OTEL_EXPORTER_OTLP_ENDPOINT
      - OTEL_EXPORTER_OTLP_HEADERS
      - OTEL_RESOURCE_ATTRIBUTES
    SYSTEMD_SERVICE: opencode
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    SYSTEMD_UNITS:
      Description: OpenCode V2 background server
      Documentation: https://opencode.ai/docs/
      Wants: network-online.target
      After: network-online.target
      StartLimitIntervalSec: 60
      StartLimitBurst: 5
    SYSTEMD_SERVICES:
      # OpenCode is an execution environment and needs the user's normal home,
      # projects, tools, and /tmp. Generic filesystem/process sandboxing would
      # silently break its core job, so harden lifecycle rather than access.
      Type: exec
      ExecStart: "{{GLOBAL_BINS_DIR}}/opencode2 serve --service --hostname ${OPENCODE_SERVICE_HOSTNAME} --port ${OPENCODE_SERVICE_PORT}"
      WorkingDirectory: "%h"
      Restart: on-failure
      RestartSec: 1
      RestartSteps: 5
      RestartMaxDelaySec: 30
      TimeoutStopSec: 30
      TimeoutStopFailureMode: kill
      KillMode: control-group
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
    ZIM_MODULES:
      - name: opencode-service-env
        phase: tools
        env:
          OPENCODE_SERVICE_URL: http://127.0.0.1:49374
        comment: Publish the local managed-service endpoint to shell clients.
      - name: opencode-service
        source: opencode-service.zsh
        phase: tools
        comment: Route both OpenCode command names through the managed V2 server.
    README: |
      # OpenCode V2 service

      OpenCode runs as the `opencode.service` systemd user unit on
      `${OPENCODE_SERVICE_HOSTNAME}:${OPENCODE_SERVICE_PORT}`. Structured logs
      are duplicated to journald and OpenCode's append-only XDG data log.

      ## Operations

          systemctl --user status opencode.service
          journalctl --user -u opencode.service -f
          systemctl --user show opencode.service \
            -p ActiveState -p SubState -p MainPID -p NRestarts \
            -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec -p TasksCurrent
          opencode2 api get /api/health
          opencode2 pair

      ## Temporary native-library cleanup

      OpenCode's compiled native dependencies can leave byte-identical hidden
      shared libraries in `/tmp`. The cleanup utility recognizes only the two
      investigated OpenTUI/FFF size and SHA-256 pairs. It never traverses
      `/tmp/opencode` and defaults to a 24-hour dry run:

          {{DIR}}/bin/cleanup.sh
          {{DIR}}/bin/cleanup.sh --min-age 72h
          {{DIR}}/bin/cleanup.sh --apply
          {{DIR}}/bin/cleanup.sh --apply --require-no-opencode

      Files mapped or held open by any process are excluded. New dependency
      versions will fail the content allowlist until they are investigated and
      explicitly added.

      The health probe must return HTTP 200. Its JSON `healthy` field remains
      true while the server is starting, stopping, or in managed boot failure.
      Do not build monitoring around the field alone, and do not probe through
      a client path that can auto-start a detached server.

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
      service deployment. If the kernel still OOM-kills a unit process,
      `OOMPolicy=stop` makes the unit fail coherently and `Restart=on-failure`
      recovers it with bounded backoff.
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
          bun install --frozen-lockfile
          bun run --cwd packages/cli build -- --single --skip-install
          bun run --cwd packages/cli build:node -- --single --skip-install
      - name: install.sh
        content: |
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
          exec bun run --cwd $DIR dev $(pwd)
      # TODO: compfuzor helpers for installing content, automate this in install-user
      - name: cleanup.sh
        basedir: False
      - name: backup.sh
        basedir: False
  tasks:
    - import_tasks: tasks/compfuzor.includes
