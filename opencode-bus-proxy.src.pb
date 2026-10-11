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
    ENV:
      # The origin: the opencode.src.pb primary, whose port authority is
      # OPENCODE_PRIMARY_PORT in vars/opencode.yaml.
      BUS_PROXY_UPSTREAM: "http://127.0.0.1:{{OPENCODE_PRIMARY_PORT}}"
      # Loopback-only; one below the origin by convention. Clients use this
      # as their server URL — opencode.src.pb derives OPENCODE_PROXY_URL
      # from the same OPENCODE_BUS_PROXY_PORT.
      BUS_PROXY_LISTEN: "127.0.0.1:{{OPENCODE_BUS_PROXY_PORT}}"
      # shared origin password: the opencode deployment's home-file view
      BUS_PROXY_PASSWORD_FILE: "{{ansible_user_dir}}/.config/opencode/secrets/OPENCODE_PASSWORD"
    busProxyService:
      SYSTEMD_SERVICE: opencode-bus-proxy
      SYSTEMD_UNITS:
        # not Requires: either side restarts independently; proxy reconnects
        Wants: opencode.service
        After: opencode.service
      SYSTEMD_SERVICES:
        Type: exec
        ExecStart: "{{GLOBAL_BINS_DIR}}/opencode-bus-proxy"
        # missing credential = deployment prerequisite; fail loudly, no crash-loop
        ExecStartPre: /bin/sh -c 'test -r "{{ansible_user_dir}}/.config/opencode/secrets/OPENCODE_PASSWORD"'
        Restart: always
    README: |
      # OpenCode bus proxy (user service)

      Gateway between clients and the managed OpenCode server. Clients use
      `http://127.0.0.1:{{OPENCODE_BUS_PROXY_PORT}}` (one port below the
      {{OPENCODE_PRIMARY_PORT}} primary) as their
      complete server URL with the usual credentials; event GETs and
      interest PUTs are owned here, everything else is forwarded (WebSocket
      upgrades tunneled). Selective delivery additionally needs the client
      setting `experimental.session_streaming: true`; without it clients
      broadcast exactly as before.

      Health is source readiness, not process liveness:

          curl -fsS -u "opencode:$(cat ~/.config/opencode/secrets/OPENCODE_PASSWORD)" \
            http://127.0.0.1:{{OPENCODE_BUS_PROXY_PORT}}/_bus/health

      `/_bus/subscriptions` answers who listens to what; `/_bus/metrics`
      exposes Prometheus counters. No replay / exactly-once: source loss
      invalidates subscriptions and clients reconnect through their
      existing logic.

      New build: `jj -R ~/src/opencode-bus-proxy bookmark set main -r <rev>`
      then rerun this playbook (it builds; installs are operator-run, the
      house convention): `sudo` may be needed for the /usr/local/bin link.
      The checkout's rust-toolchain.toml pins the compiler (1.98.0).
      Queue/limit knobs keep daemon defaults — see
      `opencode-bus-proxy --help` and
      doc/event-multiplexer/operations.md before overriding.
  tasks:
    - import_tasks: tasks/compfuzor.includes
