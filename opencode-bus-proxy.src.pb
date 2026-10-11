---
# opencode-bus-proxy (~/src/opencode-bus-proxy) as a user service:
# clients -> 127.0.0.1:49372 -> opencode.service on 49373. Requires the
# bus-smart origin (OpenCode-Event-Scope: 1; the deployed primary has it,
# verified 2026-10-11). Source is local-first: the dev checkout's `main`
# bookmark over file:// (its other remotes are unreachable from this host);
# advance the bookmark and rerun to ship a new build.
- hosts: all
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
      BUS_PROXY_UPSTREAM: "http://127.0.0.1:49373"
      # one below the origin, loopback-only; clients use this as their server URL
      BUS_PROXY_LISTEN: "127.0.0.1:49372"
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
      `http://127.0.0.1:49372` (one port below the 49373 primary) as their
      complete server URL with the usual credentials; event GETs and
      interest PUTs are owned here, everything else is forwarded (WebSocket
      upgrades tunneled). Selective delivery additionally needs the client
      setting `experimental.session_streaming: true`; without it clients
      broadcast exactly as before.

      Health is source readiness, not process liveness:

          curl -fsS -u "opencode:$(cat ~/.config/opencode/secrets/OPENCODE_PASSWORD)" \
            http://127.0.0.1:49372/_bus/health

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
