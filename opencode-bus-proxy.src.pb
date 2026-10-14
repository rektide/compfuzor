---
# opencode-bus-proxy (~/src/opencode-bus-proxy) as a user service:
# clients -> 127.0.0.1:<proxy port> -> opencode.service on <primary port>
# (both from vars/opencode.yaml, the port contract loaded by this playbook
# and opencode.src.pb alike; today 49372 -> 49373). Requires the
# bus-smart origin (OpenCode-Event-Scope: 1; the deployed primary has it,
# verified 2026-10-11). Source is local-first: the dev checkout's `main`
# bookmark over file:// (its other remotes are unreachable from this host);
# advance the bookmark and rerun to ship a new build.
- hosts: all
  vars_files:
    - vars/opencode.yaml
  vars:
    TYPE: opencode-bus-proxy
    INSTANCE: git
    REPO: "file://{{ansible_user_dir}}/src/opencode-bus-proxy"
    GIT_VERSION: main
    # the checkout's rust-toolchain.toml pins the compiler (1.98.0)
    RUST: True
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    SYSTEMD_ROOTS: [busProxyService]
    # One authored listener supplies both daemon bind and client dial defaults.
    # Both ports still come from the shared cross-playbook input above.
    _bus_proxy_listen: "127.0.0.1:{{OPENCODE_BUS_PROXY_PORT}}"
    _bus_proxy_url: "http://{{_bus_proxy_listen}}"
    ENV_CONFIG:
      projections:
        proxy-service.env:
          files: [50-proxy-service.env, 99-local-priority.env]
          format: env
        proxy-client.env.export:
          files: [60-proxy-client.env]
          format: env-export
    ENV_CONTRIBUTIONS:
      # An explicit file override replaces the credential flag, rather than
      # giving the daemon two mutually exclusive password sources.
      50-proxy-service.env: "{{ {
        'BUS_PROXY_UPSTREAM': 'http://127.0.0.1:' ~ OPENCODE_PRIMARY_PORT,
        'BUS_PROXY_LISTEN': _bus_proxy_listen
        } | combine({} if 'BUS_PROXY_PASSWORD_FILE' in (ENV_PRIO | default({}))
          else {'BUS_PROXY_CREDENTIAL': 'OPENCODE_PASSWORD'}) }}"
      60-proxy-client.env:
        OPENCODE_PROXY_URL: "{{_bus_proxy_url}}"
    # Concrete build/install/import operations own their source-order prerequisites.
    # CONFIG has no candidate dependency DAG; do not make Zim read ENV's
    # uncommitted candidate or assume a prior render assembled it.
    BINS:
      - name: status-usage.sh
        helpers: False
        basedir: False
      - name: build-proxy-env.sh
        # Both the render run lane (this bin precedes generated Rust bins)
        # and ordinary build.sh (identity/prepare before main) need ENV before Rust's
        # helper loads application defaults. Reuse normal bound CONFIG assembly.
        phase: identity
        helpers: False
        basedir: False
        bypass: False
        run: True
        content: 'exec {{ (BINS_DIR ~ "/config-assemble.sh") | quote }} --definition env --context canonical'
      - name: install-proxy-env-user.sh
        # Fresh user installs need the required EnvironmentFile before the
        # units phase, independently of the later Zim import prerequisite.
        scope: [user]
        phase: identity
        helpers: False
        basedir: False
        bypass: False
        content: 'exec {{ (BINS_DIR ~ "/config-assemble.sh") | quote }} --definition env --context canonical'
      - name: install-zimfw.sh
        early: '"$DIR/bin/config-assemble.sh" --definition env --context canonical'
    # Endpoint metadata only. Native publication/discovery owns client routing.
    # Keep the module identity so importing updates an older installed module.
    ZIM_MODULES:
      - name: opencode-bus-proxy-client-env
        source: opencode-proxy-env.zsh
        phase: 56
        comment: Publish proxy endpoint metadata after the origin credential module.
    busProxyService:
      SYSTEMD_SERVICE: opencode-bus-proxy
      SYSTEMD_UNITS:
        # not Requires: either side restarts independently; proxy reconnects
        Wants: opencode.service
        After: opencode.service
      SYSTEMD_SERVICES:
        Type: exec
        # Required service-only CONFIG output, not the whole deployment ENV
        # or SYSTEMD_ENV (which publishes to the manager).
        EnvironmentFile: "{{ ETC }}/env-projections/proxy-service.env"
        LoadCredential: "OPENCODE_PASSWORD:{{OPENCODE_PRIMARY_PASSWORDS_DIR}}/OPENCODE_PASSWORD"
        ExecStart: "{{GLOBAL_BINS_DIR}}/opencode-bus-proxy"
        # Verify systemd's runtime copy without printing the credential.
        ExecStartPre: /bin/sh -c 'test -r "$${CREDENTIALS_DIRECTORY}/OPENCODE_PASSWORD"'
        Restart: always
    README: |
      # OpenCode bus proxy (user service)

      Gateway between clients and the managed OpenCode server. Clients use
      `{{_bus_proxy_url}}` (one port below the
      {{OPENCODE_PRIMARY_PORT}} primary) as their
      complete server URL with the usual credentials; event GETs and
      interest PUTs are owned here, everything else is forwarded (WebSocket
      upgrades tunneled). Selective delivery additionally needs the client
      setting `experimental.session_streaming: true`; without it clients
      broadcast exactly as before.

      Import this deployment's Zim contribution for endpoint metadata:

          ZIM_HOST_DIR=<zim-host> {{DIR}}/bin/install-zimfw.sh

      New interactive shells export OPENCODE_PROXY_URL as metadata only.
      This module neither synthesizes nor clears OPENCODE_ARGS; deliberate
      user settings remain untouched. Its stable module identity updates old
      installed contributions in place on import. Native service discovery
      supplies client routing. No shell function, alias, or service lifecycle
      action is installed.

      Both services load the account's shared password source at
      `{{OPENCODE_PRIMARY_PASSWORDS_DIR}}/OPENCODE_PASSWORD` through systemd
      LoadCredential. The proxy uses BUS_PROXY_CREDENTIAL=OPENCODE_PASSWORD
      to read its private runtime copy under CREDENTIALS_DIRECTORY. An explicit
      ENV_PRIO BUS_PROXY_PASSWORD_FILE replaces that default credential flag.

      ENV CONFIG assembles `etc/env.d/50-proxy-service.env` and the existing
      `99-local-priority.env` into `etc/env-projections/proxy-service.env`,
      the unit's required EnvironmentFile. Discovery/watch flags below still
      add their service values to ENV_PRIO, preserving other priority keys.
      Build knobs in ordinary ENV remain command-only; use ENV_PRIO for
      explicit daemon overrides. Service selection excludes client values
      and implicit DIR/NAME/TYPE execution plumbing.

      The client module sources only the literal projection of
      `etc/env.d/60-proxy-client.env` when OPENCODE_PROXY_URL is empty/unset;
      it does not turn that metadata into CLI arguments. Neither daemon
      settings nor the full env.export are sourced into the account.
      Both projections use the same authored
      listener/port defaults, not independently maintained endpoint copies.
      The normal Zim importer reassembles ENV before importing/rebuilding its
      host cache. Standalone assembly remains available for service config:

          {{DIR}}/bin/config-assemble.sh --definition env --context canonical
          ZIM_HOST_DIR=<zim-host> {{DIR}}/bin/install-zimfw.sh

      Build/render assembles ENV before Rust; normal install-user.sh assembles
      ENV before installing units, and the normal importer also supplies
      its own prerequisite. With BINS_RUN_BYPASS=true the
      importer supplies the same prerequisite without building the daemon.
      This deployment contributes Zim material; it is not another Zim host.
      Updating files does not refresh existing shells or restart the service.

      Opt in to ordinary native discovery (not a shell wrapper) by running
      this and opencode.src.pb with `-e OPENCODE_BUS_PROXY_DISCOVERY=true`.
      Only the configured OPENCODE_DISCOVERY_FILE is contributed; no file
      is written by the playbook. The account's own origin started with
      `--publish` creates its native record; no record-init command or separate
      record maintainer is needed for an own-stack account. Use the same port
      overrides on both playbooks: zimtest owns origin 49473 / proxy 49472,
      while operator defaults remain origin 49373 / proxy 49372.
      The daemon validates forwarded /api/info
      plus source health first, retains the origin PID/version/id/password,
      and adds public endpoint markup and its own contribution PID.
      Default mode is cooperate: the new server-reg publisher chooses its
      contact via OPENCODE_PROXY_URL; the daemon only supplements it.
      Explicit `-e OPENCODE_BUS_PROXY_SERVICE_MODE=stomp` reapplies proxy
      routing whenever an eligible old/new publisher writes its origin or
      override URL. Managed/foreign records remain ineligible. The fixed
      BUS_PROXY_UPSTREAM never comes from the discovery file.

      Endpoint enrichment defaults on (OPENCODE_DISCOVERY_METADATA), but
      discovery routing itself stays opt-in. The default watcher bridge
      reuses the existing Effect FileSystemWatchClient from
      OPENCODE_BUS_PROXY_WATCH_SOURCE through Bun; it watches the parent
      directory and filters the registration filename, including atomic
      replacements. Missing helper/dependencies fall back to bounded
      polling with a warning; `-e OPENCODE_BUS_PROXY_EFFECT_WATCH=false`
      selects the standalone Rust polling path. Graceful stop restores
      only the exact last contributed record; an externally changed slot
      is left alone. The single-slot native publisher does not share the
      proxy lock, so check-plus-rename is not transactional fencing.
      This needs the new daemon flags in the selected build; generating
      config is not build installation or service activation.

      Health is source readiness, not process liveness:

          curl -fsS -u "opencode:$(cat ~/.config/opencode/secrets/OPENCODE_PASSWORD)" \
            {{_bus_proxy_url}}/_bus/health

      `/_bus/subscriptions` answers who listens to what; `/_bus/metrics`
      exposes Prometheus counters. No replay / exactly-once: source loss
      invalidates subscriptions and clients reconnect through their
      existing logic.

      Check this account's actual client connections (Linux /proc, Python 3):

          {{DIR}}/bin/status-usage.sh

      Lists OpenCode clients without an established TCP connection to
      {{_bus_proxy_listen}}, including PID, working directory, and tmux
      session/window/pane when discoverable. Server-only `serve` processes
      are excluded. Reports proxy usage/total and its ratio (ideal 1.000);
      no clients gives n/a. This is a live snapshot, not configured intent:
      disconnected/starting clients count as not using the proxy. Multiple
      sockets count once per process. A closing histogram lists every
      loopback port with established client connections and how many
      clients use each: the expected proxy port is pinned first (even at
      zero) and the rest sort ascending. No credentials or arguments are
      printed. tmux lookup uses the invoking shell's server (including
      TMUX); other tmux servers may be unavailable. Exit 0 means all
      clients use the proxy (or none exist), 1 means non-proxy clients,
      2 means incomplete inspection.

      New build: `jj -R ~/src/opencode-bus-proxy bookmark set main -r <rev>`
      then rerun this playbook (it builds; installs are operator-run, the
      house convention): `sudo` may be needed for the /usr/local/bin link.
      The checkout's rust-toolchain.toml pins the compiler (1.98.0).
      Queue/limit knobs keep daemon defaults — see
      `opencode-bus-proxy --help` and
      doc/event-multiplexer/operations.md before overriding.
  tasks:
    - name: "opencode-bus-proxy: validate discovery contribution mode"
      assert:
        that: OPENCODE_BUS_PROXY_SERVICE_MODE in ['cooperate', 'stomp']
      when: OPENCODE_BUS_PROXY_DISCOVERY|bool
    - name: "opencode-bus-proxy: opt-in native discovery environment"
      set_fact:
        ENV_PRIO: "{{ ENV_PRIO|default({}) | combine({
          'BUS_PROXY_SERVICE_FILE': OPENCODE_DISCOVERY_FILE,
          'BUS_PROXY_SERVICE_MODE': OPENCODE_BUS_PROXY_SERVICE_MODE,
          'BUS_PROXY_SERVICE_METADATA': 'true' if OPENCODE_DISCOVERY_METADATA|bool else 'false'
          }) }}"
      when: OPENCODE_BUS_PROXY_DISCOVERY|bool
    - name: "opencode-bus-proxy: reuse existing Effect watcher via Bun bridge"
      set_fact:
        ENV_PRIO: "{{ ENV_PRIO|default({}) | combine({
          'BUS_PROXY_SERVICE_WATCH_HELPER': OPENCODE_BUS_PROXY_WATCH_HELPER,
          'BUS_PROXY_SERVICE_WATCH_SOURCE': OPENCODE_BUS_PROXY_WATCH_SOURCE
          }) }}"
      when: OPENCODE_BUS_PROXY_DISCOVERY|bool and OPENCODE_BUS_PROXY_EFFECT_WATCH|bool
    - import_tasks: tasks/compfuzor.includes
