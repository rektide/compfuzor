---
type: Design inquiry
title: Self-hosted atuin sync server — init wave
description: What running our own atuin sync server for multi-machine history sync would take, researched against the v18.21.0 source.
resource: design/atuin-sync-selfhost/init0.glm53.md
tags: [atuin, sync, self-hosting, compfuzor]
status: draft
generated: { by: agent:glm53, at: 2026-09-29 }
sources:
  - id: atuin-src-18.21.0
    resource: /home/rektide/archive/atuinsh/atuin
    title: atuin source checkout, workspace version 18.21.0
  - id: atuin-docs-selfhost
    resource: https://docs.atuin.sh/self-hosting/server-setup/
    title: Atuin docs — self-hosting
---

# Self-hosted atuin sync server — init wave

## What's up

rektide runs atuin v18.21.0 on workhorse (workhorse.hosts.voodoowarez.com) as a
socket-activated per-user daemon deployed by [`atuin.src.pb`](/atuin.src.pb):
global rust build at `/usr/local/src/atuin-git`, per-user units at
`~/.config/systemd/user/atuin-daemon.{service,socket}`, state in
`~/.local/share/atuin/` (history.db 124MB, records.db 166MB). He is **not**
logged in to the central atuin.sh service and is about to set
`auto_sync = false` to silence the daemon's forever-failing "Not logged in"
sync tick. He does not want the central login system — but is curious what a
self-hosted, syncable setup would look like. Multi-machine history sync is the
goal. **This is research only, no implementation.**

Prompt for the inquiry: *what does `atuin server start` require in v18.x, how
do clients attach to our own server, does the self-hosted server fully support
the current (records) sync protocol, what would a compfuzor playbook need, and
what does the server actually get to see?*

The headline findings, before detail: postgres is **no longer** required
(SQLite is tier-one since 18.7.0); the old v1 history-table sync protocol is
**gone** (removed in 18.18.0) so client and self-hosted server speak exactly
one protocol — the records store; the self-hosted server is protocol-complete
for sync except for the optional "packfile" bandwidth optimization (Hub-only,
degraded gracefully); and history content is end-to-end encrypted so the
server only ever holds ciphertext plus coarse metadata.

All source references below are from the archive checkout at
`/home/rektide/archive/atuinsh/atuin` (workspace `version = "18.21.0"`,
`Cargo.toml`), which matches the running daemon.

## 1. The built-in server: `atuin-server start`

**It is a separate binary now, not a client subcommand.** The v18 workspace
builds `atuin-server` from `crates/atuin-server` (`crates/atuin-server/src/bin/main.rs`;
the client `crates/atuin/src` has no server subcommand). Upstream docs open
with exactly this: "The server is distributed as a separate binary,
`atuin-server`" (`docs/docs/self-hosting/server-setup.md:13-26`). The upstream
Dockerfile builds `--bin atuin-server` only (`Dockerfile:26`). So the memory
of `atuin server start` is a pre-18-ism; today it's `atuin-server start`.

**Database: postgres OR sqlite OR mysql.** This is the big change from the
"postgres historically required" era. `crates/atuin-server/src/db/` contains
`postgres/`, `sqlite/`, and `mysql/` backends behind one `DynDatabase` trait
(`crates/atuin-server/src/db/mod.rs:180-241`). Docs mark postgres + sqlite
tier-one, mysql tier-two (`server-setup.md:64-112`). SQLite support for
self-hosting landed in **18.7.0** (#2770) per `CHANGELOG.md:1084`.

**Required config** (`crates/atuin-server/src/settings.rs:53-94`,
`server.toml` example at `crates/atuin-server/server.toml`):

| Setting | Default | Notes |
| --- | --- | --- |
| `db_uri` | **none — required** | `DbSettings { db_uri }` has no default (`db/mod.rs:97-100`); e.g. `sqlite:///config/atuin.db` (file auto-created) or `postgres://user:pass@host/db` |
| `host` | `127.0.0.1` | listen addr; set `0.0.0.0` to expose |
| `port` | `8888` | |
| `open_registration` | `false` | registration closed by default — flip to `true` only while onboarding users |
| `max_record_size` | 1 GiB | per-record upload cap (`settings.rs:71`, enforced in `handlers/v0/record.rs:29-38`) |
| `path` | `""` | route prefix for reverse-proxy subdir mounts (`router.rs:141-146`) |
| `metrics.enable/host/port` | false / 127.0.0.1 / 9001 | separate prometheus listener (`settings.rs:13-29`) |
| `register_webhook_url` | none | Discord-style webhook fired on registration (`handlers/user.rs:34-56`) |
| `fake_version` | none | advertise a version other than the running one, to silence client update nagging (`settings.rs:42-47`) |

Everything is overridable via env with `ATUIN_` prefix and `__` nesting
(`settings.rs:77`) — e.g. `ATUIN_DB_URI`, `ATUIN_HOST`, `ATUIN_PORT`,
`ATUIN_OPEN_REGISTRATION`, `ATUIN_CONFIG_DIR` (that's how the Docker image
points config at `/config`). Config file is `server.toml` in the config dir,
auto-seeded from the example on first run (`settings.rs:79-88`).

**No TLS in the server.** Zero TLS settings exist; docs are blunt: "Without
TLS, passwords are sent plaintext, which is wildly insecure" — put
nginx/Caddy/Traefik in front (`server-setup.md:114-121`). Alternatives for a
homelab: keep `host = 127.0.0.1` and reach it over SSH tunnel / WireGuard /
Tailscale. The auth token rides an `Authorization: Token ...` header on every
sync request, so the transport really should not be plaintext.

There's a `/healthz` endpoint (`router.rs:136`, `handlers/health.rs`) — the
Docker image healthchecks against it (`Dockerfile:36-37`).

## 2. Client side: pointing clients at our server

- **`sync_address`** in `~/.config/atuin/config.toml` (or
  `ATUIN_SYNC_ADDRESS`), e.g. `sync_address = "https://atuin.hosts.voodoowarez.com"`.
  Docs: `docs/docs/self-hosting/usage.md:15-20`.
- **Protocol is auto-inferred**: a *custom* sync_address selects the
  "Legacy"/self-hosted protocol (`SyncProtocol::Auto` → not an official
  atuin.sh address → Legacy), which means `Authorization: Token <session>`
  auth against the OSS server's endpoints
  (`crates/atuin-client/src/settings.rs:349-399, 1238-1257`). The Hub protocol
  (Bearer `atapi_*` tokens, OAuth flow, packfiles) is what the official
  service uses; you don't get it and don't need it. There's an
  `extra_headers` map for fronting the server with Cloudflare-Access-style
  gates (`settings.rs:1065-1070`).
- **`atuin register -u <name> -e <email>`** (password prompted): POSTs
  `/register`; the server argon2id-hashes the password
  (`crates/atuin-server/src/handlers/user.rs:26-32, 104`), mints a 24-byte
  random session token (`user.rs:126`), and the client then **generates a
  PASETO v4 local key** at `~/.local/share/atuin/key`
  (`crates/atuin-client/src/register.rs:25`).
- **`atuin login -u <name>` on each additional machine**: prompts for password
  **and the key mnemonic**; if the machine already has a different key it
  re-encrypts the local store to match (`crates/atuin-client/src/login.rs:9-51`).
  Login also verifies the key can decrypt a remote record and refuses a wrong
  one (`crates/atuin/src/command/client/account/login.rs:71`).
- **Multi-device key story**: one symmetric key for the account; the first
  machine generates it, every other machine *imports* it. `atuin key` prints
  it as a mnemonic (`--base64` for raw) for the password manager
  (`crates/atuin/src/command/client/sync.rs:56-66`). A machine with the wrong
  key gets a `WrongKey` error pointing at `atuin key` + `atuin store rekey`
  (`crates/atuin-client/src/record/sync/mod.rs:77-84`). Lose the key → synced
  data is unrecoverable ("If you lose your key, we can do nothing to help
  you", `docs/docs/guide/sync.md:29`).
- **Encryption model**: records are encrypted client-side with PASETO
  v4.local, envelope-style — each record carries ciphertext plus a wrapped
  per-record CEK (`EncryptedData { raw, cek }`; implementation in
  `crates/atuin-common/src/encryption/paseto_v4.rs`). The key is a random
  32-byte key, **not** derived from the password — the password only
  authenticates you to the server; the key is what decrypts history.
- **Cadence**: `auto_sync` (default true), `sync_frequency` (default "5m"),
  daemon tick `daemon.sync_frequency` (default 300s). `atuin sync` forces a
  run, `-f` full. Session token is stored in the client's meta store
  (`settings.rs:1224-1236`) — not in config.toml.

Note for our deploy: [`atuin.src.pb`](/atuin.src.pb) already anticipates this
— the managed `auto_sync` block is *removed* when `ATUIN_AUTO_SYNC` is unset,
explicitly so that "a deliberate local override (e.g. pointing sync_address
at a self-hosted server) is never clobbered" (`atuin.src.pb:77-85, 154-165`).
A self-host switch is a per-user config.toml edit plus register/login; the
playbook needs no change to allow it.

## 3. Sync v1 vs v2 (records): what v18 actually speaks

**v18.x speaks only records sync.** The timeline from `CHANGELOG.md`:

- 18.2.0 — sync v2 (records) default for new installs (#1914, line 1449)
- 18.3.0 — upstream systemd unit for the server (#1879, line 1396)
- 18.4.0 — record sync default outright (#2255, line 1297); the old
  `[sync] records = true` toggle no longer exists in `Settings`
  (`crates/atuin-client/src/settings.rs` has no `records` field)
- 18.7.0 — sqlite server backend (#2770, line 1084)
- 18.18.0 — **v1 sync protocol removed** (#3634, line 342)

In 18.21.0 there is no v1 anywhere: the server router
(`crates/atuin-server/src/router.rs:115-146`) exposes only
`/register`, `/login`, `/user/{username}`, `/account`,
`/account/password`, `/api/v0/me`, `/api/v0/record` (GET status/POST upload),
`/api/v0/record/next` (paged download), `/api/v0/store` (DELETE wipe),
`/api/v0/capabilities`, `/healthz`. The `Database` trait has no history
methods at all (`db/mod.rs:186-209`); the `history` table that appears in the
sqlite migrations (`db/sqlite/migrations/20240108124830_create-history.sql`)
is vestigial — nothing serves it. So the question "does the self-hosted
server support v2?" inverts: **it supports nothing else**; an ancient (<15)
v1-only client cannot sync against it at all. Any "self-hosted servers only
do v1" lore predates 18.2.

**Capability negotiation — yes, and it's a hard server requirement in the
sense that the endpoints above are all a v18 client talks to.** The mechanism
(`crates/atuin-domain/src/caps/`):

- Each server advertises a JSON capability document at
  `/api/v0/capabilities`, hashed into a stable token. The client stamps
  `x-atuin-capabilities-known: <hash>` on every request; a mismatch is either
  served-anyway (`CapMismatch::Continue` — what sync uses,
  `api_client.rs:447`) or rejected 412 (`Error` mode); on mismatch the client
  refetches the document in the background (`caps/middleware.rs:20-92`). The
  axum side wires this with `negotiate_capabilities(...)`
  (`atuin-domain/src/caps/axum.rs`, used at `router.rs:120-139`).
- The self-hosted server advertises exactly two capabilities:
  `sh.atuin.server/capabilities` v1 and `sh.atuin.server/records.page_size`
  v1 with `page_size: 100` (`router.rs:104-113`).
- The daemon's sync component refreshes caps each tick —
  `handle.caps().refresh()`, failure tolerated ("keeping cached document",
  `crates/atuin-daemon/src/components/sync.rs:215-217`).

**The one real gap: packfiles.** A third capability,
`sh.atuin.server/records.packfile` (`caps/all.rs:26-51`), gates "packfile"
support — bundling many history records into one blob for transfer
efficiency (Hub backfill optimization; note packfile blobs are *not*
encrypted with the default CEK — manifests are plaintext pointers,
`record/sync/mod.rs:210-224`). The OSS server neither advertises `PackfileCap`
nor implements `/api/v0/packfiles/*` routes, and the client handles that
explicitly: "server does not advertise PackfileCap; skipping packfile
upload/download op, loose history covers it" (`record/sync/mod.rs:622-660`).
So self-hosted sync is **full-fidelity** (every record, both directions) but
loose-page only, 100 records per request page — an initial ~290MB backfill
would just take more requests, not lose data. Similarly, if a server *lacks*
the caps endpoint entirely, page size silently falls back to the client
default of 100 (`record/sync/mod.rs:157-170`) — negotiation degrades, never
breaks.

One subtlety worth knowing: the daemon **retries sync forever even with
`auto_sync = false`** if a sync fails mid-flight (Retrying state ignores the
auto_sync gate, `components/sync.rs:33-40, 149-155`) — but ticks in Idle
state are skipped entirely when not logged in, which is the behavior
`atuin.src.pb` documents. So leaving `auto_sync = false` indefinitely stays
quiet; it's only a stuck Retry loop that would keep trying.

## 4. Deployment shapes

**Official image**: `ghcr.io/atuinsh/atuin:<tagged-release>` (NOT `latest` —
docs warn against it, `docs/docs/self-hosting/docker.md:3-8`). Single-binary
container, `/config` as `ATUIN_CONFIG_DIR`, port 8888, `/healthz` healthcheck
(`Dockerfile`). Compose example pairs it with postgres:18
(`docker.md:26-53`); nothing stops you pointing `ATUIN_DB_URI` at
`sqlite:///config/atuin.db` and dropping the db container.

**Bare binary + systemd**: upstream ships a hardened unit
(`systemd/atuin-server.service`: `User=atuin`, `ATUIN_CONFIG_DIR=/etc/atuin`,
`ProtectSystem=strict`, `NoNewPrivileges`, etc., plus
`atuin-server.sysusers`), with docs at `docs/docs/self-hosting/systemd.md`.
Install via the cargo-dist installer script from GitHub releases
(`server-setup.md:15-20`), or `cargo build --bin atuin-server` from the same
checkout the client came from — for us the latter is natural since
`/usr/local/src/atuin-git` already builds v18.21.0.

**Kubernetes**: `k8s/*.yaml` (deployment + postgres + secrets), documented at
`docs/docs/self-hosting/kubernetes.md`.

**Closing registration**: yes, trivially — `open_registration` is checked
per-request at POST `/register` (`handlers/user.rs:87-90`). Register your
users, flip the flag/env to false, restart: the door is shut. There is no
admin API beyond that (no user listing, no password reset — self-service
`PATCH /account/password` and `DELETE /account` only), and a
`register_webhook_url` if you want a ping when someone signs up while open.

**A compfuzor sketch** (research-grade, not a promise):

- A `atuin-server.srv.pb`-ish playbook (server is a *service*, not a per-user
  client — different posture from `atuin.src.pb`):
  - REPO/BINS reuse the existing rust toolchain story; build
    `--bin atuin-server` from the same atuin checkout (version-locked to the
    clients by construction — nice property, given major-version skew between
    client and server breaks sync).
  - `ETC_FILES`: `server.toml` with
    `db_uri = "sqlite://{{DIR}}/atuin-server.db"` (single-user scale; postgres
    subsystem only if we ever want it), `host = "127.0.0.1"`,
    `open_registration` **false** in steady state.
  - `SYSTEMD_SCOPE: system` service unit modeled on upstream's
    (`ExecStart=<bins>/atuin-server start`; config dir via the playbook's
    `ENV:` mapping — `ATUIN_CONFIG_DIR: "{{DIR}}/etc"` — which lands in
    `{{DIR}}/env` and auto-injects `EnvironmentFile=-{{DIR}}/env`, the
    compfuzor pattern; a raw `Environment=` key is not. Values must be
    render-time absolute: EnvironmentFile never expands variables), plus
    the upstream hardening keys as a starting point.
  - TLS: bind localhost and terminate at an existing reverse proxy (caddy/
    nginx) with a real cert for e.g. `atuin.hosts.voodoowarez.com`, or skip
    the proxy and use the wireguard/tailscale mesh for transport protection.
    Either way the clients' `sync_address` needs an `https://` (or
    mesh-hostname) URL.
  - Registration bootstrap: a bin script or documented one-liner to briefly
    run with `ATUIN_OPEN_REGISTRATION=true` (env override, no file churn)
    until N users exist, then restart without it.
- Client side needs nothing new in compfuzor: per-user
  `sync_address`/`auto_sync = true` edits live outside the managed blocks by
  design; `atuin register`/`login` are per-user interactive steps anyway.

## 5. Resource & security notes

**What the server sees** — from the `store` schema
(`db/sqlite/migrations/20231203124112_create-store.sql`):

- Ciphertext: `data` (encrypted payload) + `cek` (wrapped content key). The
  server stores history, aliases, vars, and kv tags without ever holding a
  key. Docs' E2E claim holds up structurally (`docs/docs/guide/sync.md:5-6`).
- Plaintext **metadata**: `host` (a random host UUID — *not* the machine
  hostname; hostnames live inside the encrypted blob, unlike the old v1
  `history` table which had a plaintext `hostname` column), `tag`
  (`history`, `dotfiles-alias`, `dotfiles-var`, `kv`, …), `idx`, nanosecond
  `timestamp`, client record id (UUIDv7 — leaky, time-ordered), `version`,
  `created_at`, plus record *sizes*. So the operator can infer cadence of
  shell activity per host and rough data volume, but not commands, paths, or
  hostnames. The record-status index (`GET /api/v0/record`) exposes exactly
  host→tag→count to the *account owner* only.
- Auth surface: argon2id password hashes (`users` table); session tokens
  stored **plaintext** in `sessions` (24-byte base64 random) — DB read ≈ full
  account access; no token expiry in the schema; tokens sent as
  `Authorization: Token` headers → TLS (or private transport) is mandatory
  (`router.rs:24-72`). `GET /user/{username}` is unauthenticated and
  distinguishes 200/404 → username enumeration is possible on a public
  deployment. `max_record_size` bounds per-record upload; there's no quota
  system.
- Ownership/backup: sqlite backend → one file owned by the `atuin` user;
  backups are safe to ship anywhere (ciphertext + the metadata above).
  Postgres → standard pg_dump story (`docker.md:108-133` ships a daily-dump
  sidecar). Deleting your account cascades store+sessions
  (`Dialect::DELETE_*`, `db/mod.rs:113-118`).

## What a self-hosted deploy would look like for rektide

Concrete shape, given the above (still research, not a plan):

1. **Where**: workhorse already builds atuin v18.21.0; `atuin-server` is one
   more `cargo build --bin atuin-server` away, version-matched to every
   client by construction. SQLite backend keeps it a single static-ish
   service with one state file — no postgres subsystem to own. Expected
   server-side state: on first sync, the workhorse client uploads its whole
   records store (166MB local; server copy lands in the same ballpark since
   records are stored as-received).
2. **Serving**: systemd system unit (upstream's hardened unit as the base),
   `127.0.0.1:8888`, TLS via an existing reverse proxy hostname or the
   wireguard mesh. `open_registration = true` for the minutes it takes to
   `atuin register` one user, then false forever.
3. **First client (workhorse)**: `sync_address` in config.toml outside the
   managed blocks (the playbook preserves it), flip `auto_sync = true` (or
   unset the managed false), `atuin register` — generates the account key —
   then `atuin sync`; the client notices history.db (124k rows worth) is
   ahead of the records store and auto-initializes it into encrypted records
   before uploading (`crates/atuin/src/command/client/sync.rs:102-126`).
4. **Other machines**: `atuin login -u rektide` + key mnemonic from
   `atuin key` on workhorse (store that mnemonic in the password manager —
   it's the only decryptor). Sync frequency 5m default via each machine's
   daemon.
5. **Rollback**: `auto_sync = false` again; nothing local is lost — the
   local databases remain the source of truth on each machine.

Total moving parts: one unit, one config file, one sqlite file, one TLS
route, and per-client config.toml edits. That's dramatically lighter than the
"postgres required" lore suggests — the sqlite backend is the whole reason
this is a small commit rather than an infrastructure project.

## Open questions

- **Hub self-hosting**: `hub_endpoint()` suggests a self-hostable Hub exists
  (`settings.rs:275-1286`), and the repo has an excluded `ui/backend`
  workspace member — but no OSS Hub server ships here. Presumably a hosted
  product; the legacy-protocol OSS server is the self-hosting surface. Worth
  confirming nothing we'd want (packfiles?) is Hub-exclusive-by-necessity
  vs just not-yet-OSS.
- **Client/server version skew**: the semver middleware hints sync is
  same-major-version only (`router.rs:90-96`). If we ever pin clients to
  stable releases while tracking git on the server (or vice versa), what
  breaks first? Our version-locked build sidesteps this, but a release-upgrade
  policy is worth a line in a future playbook.
- **TOTP**: `atuin login --toto-code` exists client-side
  (`account/login.rs:24-26`); the OSS server handlers don't reference it.
  Hub feature, presumably — confirm it's simply ignored.
- **Page size 100 on backfill**: fine at our scale, but if the initial upload
  of a ~166MB store is sluggish, is there a server-side knob (a custom
  PageSizeCap via config?) or is 100 hardcoded (`router.rs:108-112` looks
  hardcoded — a patch would be trivial if we ever cared).
- **Key rotation / device revocation**: sessions are per-login tokens with no
  listing/revocation UI in the OSS server; is `atuin logout` device-local
  only, and does rotating the key (`store rekey`) re-upload everything
  cleanly? Low stakes with one user, but worth knowing before adding devices.

## References

**Source (archive checkout, v18.21.0):**

- `crates/atuin-server/src/settings.rs` — server settings, env mapping, defaults
- `crates/atuin-server/src/router.rs` — full route surface, caps registration (CapabilitiesCap, PageSizeCap)
- `crates/atuin-server/src/handlers/user.rs` — register/login, argon2id, session minting, open_registration gate
- `crates/atuin-server/src/handlers/v0/record.rs` — record upload/index/next handlers, max_record_size
- `crates/atuin-server/src/db/mod.rs` — DynDatabase trait, DbSettings (db_uri required), dialect SQL
- `crates/atuin-server/src/db/sqlite/migrations/20231203124112_create-store.sql` — records store schema (server-visible metadata)
- `crates/atuin-client/src/settings.rs` — sync_address/sync_protocol/SyncAuth, is_hub_sync, resolve_sync_auth
- `crates/atuin-client/src/record/sync/mod.rs` — SyncEngine: diff/ops/upload/download, WrongKey, PageSizeCap fallback, PackfileCap gating
- `crates/atuin-client/src/record/sync/builder.rs` — engine construction, caps injection
- `crates/atuin-client/src/api_client.rs` — endpoints, Token/Bearer auth, CapMismatch::Continue
- `crates/atuin-client/src/register.rs`, `src/login.rs` — register/login flows, key generation/import
- `crates/atuin-client/src/encryption` — (key handling lives in `atuin-common`)
- `crates/atuin-common/src/encryption/paseto_v4.rs` — PASETO v4.local envelope encryption, mnemonic encoding
- `crates/atuin-domain/src/caps/{mod,all,client,middleware}.rs` — capability protocol design doc + implementation
- `crates/atuin-daemon/src/components/sync.rs` — daemon sync loop, auto_sync gating, retry/backoff
- `crates/atuin/src/command/client/sync.rs` — `atuin sync`/`key` commands, store auto-init
- `systemd/atuin-server.service` — upstream hardened unit
- `Dockerfile`, `k8s/atuin.yaml` — container/k8s shapes
- `CHANGELOG.md` — version landmarks: 18.2.0 sync-v2 default, 18.4.0 records default, 18.7.0 sqlite server, 18.18.0 v1 removed

**Docs (in-repo, mirrored at https://docs.atuin.sh):**

- `docs/docs/self-hosting/server-setup.md` — https://docs.atuin.sh/self-hosting/server-setup/
- `docs/docs/self-hosting/usage.md` — https://docs.atuin.sh/self-hosting/usage/
- `docs/docs/self-hosting/docker.md` — https://docs.atuin.sh/self-hosting/docker/
- `docs/docs/self-hosting/kubernetes.md` — https://docs.atuin.sh/self-hosting/kubernetes/
- `docs/docs/guide/sync.md` — https://docs.atuin.sh/guide/sync/ (register/login/key flow)

**Local:**

- [`atuin.src.pb`](/atuin.src.pb) — current client deploy; `ATUIN_AUTO_SYNC` managed-block design that deliberately preserves a local self-hosted `sync_address` override
