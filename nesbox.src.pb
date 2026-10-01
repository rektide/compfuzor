---
# NESBox -- mantou132's online multiplayer retro-game platform
# (https://github.com/mantou132/nesbox, default branch `dev`).
#
# Architecture (all on this host, no VM/container needed -- see README):
#   nesbox-git.service   Rust actix-web GraphQL API, :8080
#                        (`cargo build -p server`, package name is literally
#                        `server`; installed as nesbox-server)
#   postgresql 16        role/db `nesbox`; diesel migrations applied by
#                        install-db.sh via psql (migrations are plain SQL,
#                        bookkept in __diesel_schema_migrations)
#   nesbox-web.service   caddy file_server on :8090 serving the built webapp
#                        ({{VAR}}/www) and reverse-proxying /api/* -> :8080
#                        (strip prefix; graphql POST + ws /subscriptions)
#
# The webapp builds without API_BASE, so it defaults to `/api` (same-origin
# through caddy). Emulator cores are consumed from npm (@mantou/nes,
# @nesbox/fceux, ruffle), so no wasm toolchain is needed; graphql codegen
# output is committed (src/generated/).
#
# Secrets: PASSWORDS generates (and persists under {{ETC}}/secrets) the DB
# password and the JWT SECRET. They reach the server via ENV -> {{DIR}}/env ->
# EnvironmentFile, which PID1 reads as root; the unit itself stays secret-free
# and the nesbox user never needs to read {{DIR}}.
#
# Flow: the playbook clones (submodules off), cargo-builds the server
# (build-rust.sh, auto) and builds the webapp (build-web.sh, auto). Then:
#   sudo bash {{DIR}}/bin/install.sh    # apt -> binary -> web -> db -> units
#   # play: http://<host>:8090
- hosts: all
  vars:
    TYPE: nesbox
    INSTANCE: git
    REPO: https://github.com/mantou132/nesbox

    # --- server (Rust) ---
    # RUST_PKG selects the `server` workspace member; its binary is
    # target/release/server. That name is too generic for GLOBAL_BINS_DIR, so
    # install-rust.sh is tombstoned and install-server.sh lands it as
    # nesbox-server (real file: the nesbox user cannot traverse {{DIR}}).
    RUST: True
    RUST_PKG: server

    PASSWORDS:
      # names must be valid variable names (PASSWORDS unpacks each into one)
      - name: nesbox_db
        format: openssl rand -hex 24   # hex: URL-safe inside DATABASE_URL
        file: true
      - name: nesbox_jwt
        format: openssl rand -hex 32
        file: true

    # Consumed by the server unit (EnvironmentFile={{DIR}}/env, injected by
    # SYSTEMD_SERVICES_DEFAULT because ENV is a mapping) and by install-db.sh.
    ENV:
      DATABASE_URL: "postgres://nesbox:{{PASSWORD.nesbox_db}}@127.0.0.1:5432/nesbox"
      SECRET: "{{PASSWORD.nesbox_jwt}}"
      PORT: "8080"

    # --- API server unit ---
    SYSTEMD_SYSUSER: True
    SYSTEMD_USER: nesbox
    SYSTEMD_UNITS:
      Description: NESBox -- online multiplayer retro-game platform (API)
      Documentation: https://github.com/mantou132/nesbox
      After: network-online.target postgresql.service
      Wants: network-online.target
    SYSTEMD_SERVICES:
      Type: simple
      User: nesbox
      Group: nesbox
      ExecStart: "{{GLOBAL_BINS_DIR}}/nesbox-server"
      Restart: on-failure
      RestartSec: "3"
      NoNewPrivileges: "yes"
      CapabilityBoundingSet: ""
      PrivateTmp: "yes"
      PrivateDevices: "yes"
      ProtectSystem: strict
      ProtectHome: "yes"
      ProtectClock: "yes"
      ProtectHostname: "yes"
      ProtectControlGroups: "yes"
      ProtectKernelTunables: "yes"
      ProtectKernelModules: "yes"
      ProtectKernelLogs: "yes"
      ProtectProc: invisible
      RestrictNamespaces: "yes"
      RestrictRealtime: "yes"
      RestrictSUIDSGID: "yes"
      LockPersonality: "yes"
      MemoryDenyWriteExecute: "yes"
      RemoveIPC: "yes"
      RestrictAddressFamilies: "AF_INET AF_INET6 AF_UNIX"
      UMask: "0027"
    SYSTEMD_INSTALLS:
      WantedBy: multi-user.target

    # --- web frontend unit (second unit via SYSTEMD_ROOTS) ---
    SYSTEMD_ROOTS: [nesboxWeb]
    nesboxWeb:
      SYSTEMD_SERVICE: nesbox-web
      SYSTEMD_UNITS:
        Description: NESBox web frontend (caddy static + /api proxy)
        Documentation: https://github.com/mantou132/nesbox
        After: network-online.target {{NAME}}.service
        Wants: network-online.target
      SYSTEMD_SERVICES:
        # inherits User/Group/hardening from the top-level SYSTEMD_SERVICES
        ExecStart: "/usr/bin/caddy run --config {{ETC}}/nesbox-web.Caddyfile --adapter caddyfile"
        # {{VAR}} == /var/lib/{{NAME}}: install-web.sh stages dist/ here (the
        # nesbox user cannot traverse {{DIR}}/repo); StateDirectory (with
        # ProtectSystem=strict) makes it writable and systemd chowns on start.
        StateDirectory: "{{NAME}}"
      SYSTEMD_INSTALLS:
        WantedBy: multi-user.target

    ETC_PROP:
      mode: "0755"   # nesbox user must traverse {{ETC}} for the Caddyfile
    ETC_FILES:
      - name: nesbox-web.Caddyfile
        mode: "0644"
        content: |
          # Generated by compfuzor/nesbox.src.pb
          # Static webapp (vite bundle) + same-origin /api proxy to the API
          # server. The webapp is built without API_BASE, so it calls /api/*
          # (graphql POST + websocket /subscriptions upgrades transparently).
          {
            admin off
          }
          :8090 {
            root * {{VAR}}/www
            # vite emits content-hashed assets/
            @hashed path /assets/*
            header @hashed Cache-Control "public, max-age=31536000, immutable"
            handle_path /api/* {
              reverse_proxy 127.0.0.1:8080
            }
            # SPA history-API routing (upstream's vercel.json rewrites all -> /)
            handle {
              try_files {path} /index.html
              file_server
            }
          }

    BINS:
      # install-rust.sh would link GLOBAL_BINS_DIR/server -- too generic a
      # name. Tombstone it and land the binary properly named below.
      - name: install-rust.sh
        state: absent
      - name: install-server.sh
        exec: |
          sudo install -Dm0755 "$DIR/repo/target/release/server" "{{GLOBAL_BINS_DIR}}/nesbox-server"
      - name: build-web.sh
        run: True
        basedir: repo
        exec: |
          # yarn 1 workspace install + vite build. The repo pins
          # packageManager yarn@1.22.22, but mise's yarn is 4.x and not
          # corepack-aware, so invoke the pinned major explicitly via npx.
          npx --yes yarn@1.22.22 install --frozen-lockfile
          npx --yes yarn@1.22.22 workspace @nesbox/webapp run build
      - name: install-web.sh
        exec: |
          sudo install -d -m 0755 -o nesbox -g nesbox "{{VAR}}/www"
          sudo rsync -a --delete "$DIR/repo/packages/webapp/dist/" "{{VAR}}/www/"
      - name: install-db.sh
        exec: |
          set -e
          # local postgres: umbrella unit starts every cluster (16/main)
          sudo systemctl enable --now postgresql

          DB_PASS="$(printf '%s' "$DATABASE_URL" | sed -nE 's#^postgres://[^:]+:([^@]+)@.+#\1#p')"
          [ -n "$DB_PASS" ]

          sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='nesbox'" | grep -q 1 || \
            sudo -u postgres psql -v pw="$DB_PASS" -c "CREATE ROLE nesbox LOGIN PASSWORD :'pw'"
          sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='nesbox'" | grep -q 1 || \
            sudo -u postgres createdb -O nesbox nesbox

          # diesel migrations are plain SQL dirs; replay the bookkeeping
          # diesel_cli would do so `cargo diesel` never has to run here.
          psql "$DATABASE_URL" -c "CREATE TABLE IF NOT EXISTS __diesel_schema_migrations (version VARCHAR(50) PRIMARY KEY NOT NULL, run_on TIMESTAMP NOT NULL DEFAULT NOW())"
          for mig in "$DIR/repo/packages/server/migrations"/*/; do
            [ -f "$mig/up.sql" ] || continue
            ver="$(basename "$mig")"
            psql "$DATABASE_URL" -tAc "SELECT 1 FROM __diesel_schema_migrations WHERE version='$ver'" | grep -q 1 || {
              echo "applying $ver"
              psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$mig/up.sql"
              psql "$DATABASE_URL" -c "INSERT INTO __diesel_schema_migrations(version) VALUES('$ver')"
            }
          done

    PKGS:
      - build-essential
      - pkg-config
      - libssl-dev          # openssl crate
      - libpq-dev           # diesel postgres (libpq-sys)
      - postgresql          # server; 16/main cluster pre-exists here with
      - postgresql-client   # binaries_missing -- reinstall restores them
      - caddy               # nesbox-web static + /api proxy
      - rsync               # dist -> {{VAR}}/www
      - ca-certificates

    README: |
      # NESBox

      mantou132's online multiplayer retro-game platform (NES/FC, arcade,
      Flash, wasm4...): a Rust GraphQL server with Postgres, a vite webapp,
      and WebRTC voice. Built from source ({{REPO}}) and run as two hardened
      system services -- no VM or container involved; it is just a web
      service, so plain systemd + a dedicated `nesbox` user is the whole
      sandbox story.

      ## Run / iterate

          ansible-playbook -i 'localhost,' -c local nesbox.src.pb   # clone+build (rust, web)
          sudo bash {{DIR}}/bin/install.sh    # apt -> nesbox-server -> web -> db -> units
          # play at http://<host>:8090

      Iterate without side effects:

          ansible-playbook -i 'localhost,' -c local nesbox.src.pb \
            -e PKGS_BYPASS=True -e APT_BYPASS=True -e REPO_BYPASS=True \
            -e BINS_RUN_BYPASS=True -e SYSTEMD_THUNK_BYPASS=True

      Build deps beyond PKGS: rust + node via mise (build-rust.sh uses cargo,
      build-web.sh uses `npx yarn@1.22.22`); psql for migrations.

      ## Games

      The database starts empty. Seed the upstream catalog:

          curl -LO https://github.com/mantou132/nesbox/releases/download/0.0.1/games.sql
          psql "$DATABASE_URL" -f games.sql

      or publish games through a GitHub-issue webhook (see
      packages/server/README.md upstream) -- it is only reachable if you
      expose :8080's /webhook and set SECRET (already set here).

      ## Locations

      | what        | where                                        |
      |------------|----------------------------------------------|
      | API binary  | /usr/local/bin/nesbox-server                 |
      | API service | {{NAME}}.service (alias nesbox.service), :8080 |
      | web service | nesbox-web.service (caddy), :8090             |
      | web static  | {{VAR}}/www (StateDirectory, rsync'd)         |
      | Caddyfile   | {{ETC}}/nesbox-web.Caddyfile                  |
      | env/secrets| {{DIR}}/env (PID1-read), {{ETC}}/secrets/     |
      | database    | postgres 16/main, role+db `nesbox`           |

      GraphQL playground: http://<host>:8080/playground (guest: /guestplayground).

      ## Desktop client

      The tauri desktop/mobile clients can point at a custom server; the
      browser at :8090 needs nothing.
  tasks:
    - import_tasks: tasks/compfuzor.includes
