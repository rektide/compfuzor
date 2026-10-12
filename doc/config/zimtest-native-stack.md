---
type: Verification
title: Zimtest's own native OpenCode and proxy stack
description: Independent ports and credential, systemd credential copies, install ordering and native discovery without OPENCODE_ARGS.
resource: /doc/config/zimtest-native-stack.md
status: verified-live
generated: {by: "model:openai/gpt-6-astra", at: "2026-10-12"}
sources:
  - resource: "opencode://ses_ed2784f73ffeAAzhSikmZhbXAr"
    title: User-selected own-stack topology, per-account LoadCredential wiring, live installation and restart verification
  - resource: "opencode://ses_ed1d41e9fffeIR6qKRWHq4Of7H"
    title: Native client and proxy investigation; existing contribution suffices when the account owns both services
  - resource: "opencode://ses_ed0de28bbffeY4IOpNy65g36sM"
    title: Proxy credential projection, removal of argument routing and install prerequisite ordering
  - resource: /vars/opencode.yaml
    title: Shared port and primary credential-directory defaults
  - resource: /opencode.src.pb
    title: Own-account foreground publisher, credential source and systemd copy
  - resource: /opencode-bus-proxy.src.pb
    title: Native record contribution, service ENV projection and LoadCredential consumer
  - resource: /doc/config/definitions.md
    title: Exact ENV contribution selection for command, service and metadata outputs
  - resource: /doc/config/zimtest-rehearsal.md
    title: Historical bootstrap fixes and superseded shared-endpoint and OPENCODE_ARGS trials
  - resource: file:///home/rektide/src/opencode-bus-proxy/doc/event-multiplexer/operations.md#native-local-discovery
    title: Existing native contribution, stomp, republication and graceful-restoration contract
verification:
  command: sudo -u zimtest -H python3 /home/zimtest/zimtest-account.py --http --services
  scope: Live native discovery in both shell modes, separate authentication domains, service credential copies and origin restart republication
---

# Zimtest's own native stack

**Plain OpenCode now discovers zimtest's own proxy without `OPENCODE_ARGS`, a
wrapper, or an explicit `--server`.** The account owns both services and their
data. This is the current landing, superseding the
[earlier shared-endpoint rehearsal](/doc/config/zimtest-rehearsal.md).

| Account | Proxy | Origin | Credential source |
|---|---|---|---|
| rektide | `127.0.0.1:49372` | `:49373` | Its existing private source |
| zimtest, UID 61019 | `127.0.0.1:49472` | `127.0.0.1:49473` | `/home/zimtest/.config/opencode/secrets/OPENCODE_PASSWORD` |

The two passwords differ; both proxies rejected the other account's password.
The earlier temporary copy of the operator's password was replaced with
zimtest's originally generated independent password before starting its server.
The operator's two services were not restarted.

```sh
sudo -iu zimtest
opencode
opencode api get /_bus/health
python3 ~/zimtest-account.py --http --services
```

The [probe source](/tests/integration/zimtest_account.py) is also reusable on a
prepared account. It verifies plain native API discovery in **both** interactive
and noninteractive login shells; the noninteractive shell has no exported
OpenCode password or interactive endpoint module. It validates origin/proxy
identity, private native state, Zim/Mise status and live credential copies without
printing secrets. No model requests were made. Provider login/configuration is
separate from this service and shell verification.

## Native initialization and refresh

1. The account's `opencode.service` runs foreground `serve --publish` on 49473.
   It creates `~/.local/state/opencode/service-local.json` with `mode:"server"`,
   its PID/version and the account's credential.
2. Its proxy starts on 49472 and selects **that same account's file** through
   `BUS_PROXY_SERVICE_FILE`. It verifies authenticated forwarded identity and
   source health, then contributes the proxy URL in explicit **stomp** mode.
3. Ordinary clients discover the file. Zim exports endpoint **metadata** and
   the client credential pointer; it performs no routing and sets no arguments.

The proxy already supports the required record update. An extra `client-record`
command and separate background maintainer were considered while the topology
was ambiguous, then dropped once the user selected an own-origin/own-proxy stack.
No such capability was landed.

The user selected explicit lifecycle actions rather than a new automatic
maintainer. Restarting the origin is an explicit systemd action; its existing
native publisher writes fresh identity, and the proxy's already-supported
contribution loop reapplies its URL to the new record. This was tested live:
the origin PID changed, the native record returned to 49472, its password stayed
stable, and the full account probe passed again. Normal proxy shutdown retains
the existing contributor semantics: it restores the preceding direct contact
when it still owns the exact record.

**Client `service.disabled` must be unset or false.** True selects a private
standalone server before discovery; the earlier claim that it merely prevented
managed startup was incorrect. It was unset in zimtest after the native record
was established:

```sh
opencode service unset disabled
```

No OpenCode rebuild was needed for this landing. The origin/client is the known
installed `0.0.0-local-202610110425` build, copied to zimtest's `~/.local/bin`.
The current proxy source was built with `cargo build --release --locked` and its
standalone executable installed in the same account directory. This proxy has
the newer discovery-contribution flags missing from the operator's older proxy.
Neither source build selection nor this target-only binary copy advances a
production bookmark or replaces the operator's binary.

The late server-reg publisher's `OPENCODE_PROXY_URL` / `--publish-url` capability
still belongs to phase 2+3 composition. Stomp supports the current older publisher
now; cooperate can be selected deliberately once the publisher itself chooses
the proxy contact. Exporting `OPENCODE_PROXY_URL` in a client shell is not that
publisher integration.

## Per-account credentials

The origin owns the persistent source. Both playbooks derive the primary source
directory from `OPENCODE_PRIMARY_PASSWORDS_DIR`, defaulting to the invoking
account's `~/.config/opencode/secrets`. Secondary origin instances retain their
instance-specific source directories.

```sh
~/src/opencode-git/bin/credential.sh ensure
~/src/opencode-git/bin/credential.sh status
```

`ensure` creates a random source only when absent, atomically publishes without
replacing another ensure's result, and enforces directory 0700 / file 0600.
Existing passwords are never rotated. It rejects symlink/nonregular/foreign-owned
sources and invalid empty/multiline passwords; it never prints the value.
`status` is read-only. `install-credential-user.sh` places ensure in the generated
user install lane ahead of the systemd operations.

Both user units use:

```ini
LoadCredential=OPENCODE_PASSWORD:/home/zimtest/.config/opencode/secrets/OPENCODE_PASSWORD
```

- Origin: its unit-only `env-credential` points `OPENCODE_PASSWORD_FILE` at
  `/run/user/61019/credentials/opencode.service/OPENCODE_PASSWORD`.
- Proxy: its selected service ENV has `BUS_PROXY_CREDENTIAL=OPENCODE_PASSWORD`;
  the daemon reads its own copy under `$CREDENTIALS_DIRECTORY`.
- Both unit prechecks verify the runtime credential route. Live copies are
  private and byte-identical to the source. Neither server process exports the
  password value in its environment.

After an intentional source replacement, restart **both account units** to
refresh their systemd snapshots. No automatic rotation or cross-account secret
copying is installed. Native discovery itself contains the credential under its
normal private 0600 state-file contract.

## Deployment inputs and install ordering

The same explicit inputs were used on both target playbooks:

```json
{
  "USERMODE": true,
  "OPENCODE_PRIMARY_PORT": 49473,
  "OPENCODE_BUS_PROXY_PORT": 49472,
  "OPENCODE_SERVER_HOSTNAME": "127.0.0.1",
  "OPENCODE_BUS_PROXY_DISCOVERY": true,
  "OPENCODE_BUS_PROXY_SERVICE_MODE": "stomp",
  "OPENCODE_BUS_PROXY_EFFECT_WATCH": false
}
```

For this binary-bootstrap rehearsal, repository fetching, generated build runs,
global-bin replacement and automatic systemd thunk were bypassed. User units
were generated and installed explicitly. The origin additionally used
`ENV_PRIO` selecting `OPENCODE_WATCHER_BACKEND=parcel` and
`OPENCODE_FFF_WATCH=native`, because zimtest has no Watchman service. Do not pass
an extra-vars `ENV_PRIO` into the proxy render: that would mask its conditional
discovery `set_fact` additions. Its native Rust polling path was selected instead
of the optional Bun/Effect watcher bridge.

As the account, after render and binary provisioning:

```sh
~/src/opencode-git/bin/install-credential-user.sh
~/src/opencode-git/bin/install-service-opencode-user.sh
~/src/opencode-bus-proxy-git/bin/build-proxy-env.sh
~/src/opencode-bus-proxy-git/bin/install-service-opencode-bus-proxy-user.sh

ZIM_HOST_DIR="$HOME/.local/opt/zim2-main" ~/src/opencode-git/bin/install-zimfw.sh
ZIM_HOST_DIR="$HOME/.local/opt/zim2-main" ~/src/opencode-bus-proxy-git/bin/install-zimfw.sh
opencode service unset disabled
```

The ordinary proxy user-install aggregate now has an identity-phase
`install-proxy-env-user.sh` prerequisite so its required service ENV is assembled
**before** systemd starts it. The lower-level unit installer above assumes its
explicit preceding assembly. The importer also assembles its own ENV prerequisite.
These reuse [selected ENV CONFIG outputs](/doc/config/definitions.md), not shell
exports of the entire daemon environment.

`loginctl enable-linger zimtest` and `systemctl start user@61019.service` supplied
the target user manager. Sudo-driven user-manager commands used
`XDG_RUNTIME_DIR=/run/user/61019` and
`DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/61019/bus`.

## Verification and remaining boundaries

- Private credential command: create, repeat without rotation, permission repair,
  read-only status and empty/symlink/FIFO refusal tests pass.
- Both live services: native discovery, authentication and LoadCredential checks pass.
- Origin restart: fresh identity plus reapplied proxy contact verified; probe passes afterward.
- Accounts: distinct passwords and cross-account rejection verified.
- Shells: no `OPENCODE_ARGS`, no function wrapper, both login modes pass.
- Zim2 now puts `~/.local/bin` ahead of shared commands in zimenv phase 25,
  after Mise activation. This also corrects an already-cached Mise activation
  script that had captured the earlier PATH without user binaries. Both shell
  modes select zimtest's own OpenCode executable, not the operator's global
  binary, keeping future build/version changes independent.
- The original optional-tool module disables and local zim-opencode completion
  patch remain as recorded in the historical rehearsal. Publish that module fix
  before expecting a fresh deck clone to inherit it.
- Target user manager is degraded by unrelated system-provided `mpd` and `ydotool`
  failures. The two OpenCode units are independently active and healthy.
- The full operator-oriented OpenCode status includes cleanup timers, working-tree
  link assertions and Watchman/shared-FFF defaults not adopted by this contained
  binary-bootstrap account. Those are not claimed as passing here.
- The explicit origin credential/unit installers were exercised, not the full
  legacy origin `install-user.sh` body (whose TARGET/config-link behavior still
  needs attention). A generated deployment config is not proof of account config
  adoption; this account currently uses its fresh native defaults.

For **deck**, use an account-owned origin/proxy pair, check available ports, and
provision its own credential source before installing its units. The port pair
can be 49373/49372 if free there; this host's 49473/49472 selection is an explicit
collision avoidance choice, not an arithmetic account-port allocator. The same
native initialization and credential-copy path applies.
