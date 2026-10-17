---
type: Verification
title: Fresh-account Zim2, Mise2 and OpenCode rehearsal
description: Live zimtest results, reproducible activation, proxy-owned Zim routing defaults and remaining bootstrap gaps before deck.
resource: /doc/config/zimtest-rehearsal.md
status: historical
generated: {by: "model:openai/gpt-6-astra", at: "2026-10-12"}
sources:
  - resource: "opencode://ses_ed2784f73ffeAAzhSikmZhbXAr"
    title: Live fresh-account iteration and correction completing proxy-owned Zim routing without explicit client flags
  - resource: /user-test.etc.pb
    title: Reserved-band account factory
  - resource: /zim2.opt.pb
    title: Experimental user-context Zim host
  - resource: /mise2.opt.pb
    title: Isolated Mise config and early Zim contribution
  - resource: /vars/opencode.yaml
    title: Shared origin and proxy port contract
  - resource: /doc/config/consumer-toolkit.md#zim-complete-installation
    title: Explicit host import and canonical registry semantics
  - resource: file:///home/rektide/src/opencode-bus-proxy/doc/event-multiplexer/discovery-verification.md
    title: Prior source-only discovery verification and unactivated build boundary
  - resource: https://opencode.ai/v2/docs/cli
    title: V2 explicit-server CLI and service-disable behavior
verification:
  scope: Live shell activation and native environment-routed authenticated GETs through the existing proxy; native proxy discovery remains unactivated
  command: sudo -u zimtest -H python3 /home/zimtest/zimtest-account.py --http
---

# Fresh-account rehearsal

**Historical rehearsal, superseded by [zimtest's own native stack](/doc/config/zimtest-native-stack.md).**
The shared-endpoint credential and OPENCODE_ARGS trial below have been replaced
by ports 49473/49472, an independent account credential, two LoadCredential user
units and native discovery. The earlier `disabled=true` interpretation was wrong
and that setting has been unset. The sections below preserve the earlier work
and its bootstrap findings rather than describe the current routing.

`zimtest` (UID/GID **61019**, private home `/home/zimtest`, Zsh) is usable for
shell testing. Both clean login modes pass; interactive shells load the OpenCode
credential and corrected completions. Zim's full `status.sh`, direct
`status-zim.sh`, and Mise2's `status.sh` pass after rerender/reinstall.

```sh
sudo -iu zimtest
# In that interactive shell:
opencode
# Or an informational probe, also without an explicit --server:
opencode api get /_bus/health
python3 ~/zimtest-account.py --http
```

The proxy's imported Zim module now sets native `OPENCODE_ARGS` defaults, so
ordinary `opencode` uses **49372**. The earlier rehearsal stopped at explicit
server access and missed this requested outcome; the correction adds the proxy
producer and strengthens the live probe to require a proxy-only endpoint with
no explicit server argument.

For an explicit override, the CLI's `--server` must follow `api` in this deployed build. The root-first
`opencode --server URL api ...` form fails with an unrecognized-flag error.
For the TUI, the root form `opencode --server URL` is appropriate.

The repeatable [account probe](/tests/integration/zimtest_account.py) starts with
a clean environment and HOME cwd, uses a PTY for interactive Zsh, checks the
actual Mise setting, credential loading, absence of an OpenCode shell wrapper,
completion cache, proxy routing defaults, activation status, and optionally CLI/API access. It compares
origin/proxy `/api/info` and requires `opencode api get /_bus/health` readiness
without explicit routing flags. It prints no
credential or API response. The optional HTTP checks perform GETs only.

## What the port proof establishes

Both source playbooks rendered successfully as the target user with
`OPENCODE_BUS_PROXY_DISCOVERY=true` and deployment effects bypassed:

| Generated setting | Value |
|---|---|
| `OPENCODE_SERVER_PORT` / `OPENCODE_SERVER_URL` | `49373` / `http://127.0.0.1:49373` |
| Native publisher `OPENCODE_PROXY_URL` | `http://127.0.0.1:49372` |
| Proxy `BUS_PROXY_UPSTREAM` | `http://127.0.0.1:49373` |
| Proxy `BUS_PROXY_LISTEN` | `127.0.0.1:49372` |
| Proxy contribution mode | `cooperate` |
| Target discovery file | `/home/zimtest/.local/state/opencode/service-local.json` |

Both OpenCode and proxy producers were imported into Zim2. New interactive
shells get the origin URL, port and credential pointer at phases 54/55, then
the proxy's phase-56 module exports `OPENCODE_PROXY_URL` and
`OPENCODE_ARGS="--server http://127.0.0.1:49372"`. These are native CLI defaults,
not a shell function or alias. Existing nonempty OPENCODE_ARGS is preserved;
explicit --server/--standalone choices override environment defaults in the
native CLI argument preparation. **Do not change the
origin's port to 49372 to make a shell variable look like the proxy.**

Actual HTTP tests reach the existing **rektide-owned** origin/proxy, not newly
started services under zimtest. Its origin identity was PID 1783, version
`0.0.0-local-202610110425`; both endpoints returned identical info. A deliberate
0600 copy of the existing server credential was provisioned into the target's
`~/.config/opencode/secrets/OPENCODE_PASSWORD`. Its initial generated credential
is retained beside it as `OPENCODE_PASSWORD.generated`. No provider credentials
were copied. Connecting this account to that server still executes server work
as the server's owner; this rehearsal only made informational requests.

Native discovery publication is **pending phase 2+3 integration**. The live operator record
still advertises `http://0.0.0.0:49373`; the installed proxy's help lacks the new
discovery flags. The earlier [discovery receipt](file:///home/rektide/src/opencode-bus-proxy/doc/event-multiplexer/discovery-verification.md)
explains the source-only proof. Compose/build/activate the late publisher and
proxy work, then verify `--publish-url` / `OPENCODE_PROXY_URL` publication and
discovery with shell routing defaults unset. Neither live service was restarted here.

The target has no native service registration. `opencode service set disabled
true` was applied **to zimtest only**, preventing accidental stock-service
startup during the rehearsal. The imported proxy defaults route clients without
depending on managed-service startup. Later, deliberately enable the desired
native account topology.

## Reproduce activation

The operator created the account with:

```sh
ansible-playbook -i 'localhost,' -c local user-test.etc.pb -e USER_TEST_USERS=zimtest
```

Prepare a readable checkout **owned by the target**. Here, selected Compfuzor
source/runtime directories were copied to `~/src/compfuzor`; the operator's
`zim2.opt.pb` was mode 0600 and could not be read directly. Create intermediate
directories as the target too: an initial root-owned `~/src` caused a spurious
sudo requirement, corrected by changing that one directory's ownership.

From the target's checkout, in a clean target environment:

```sh
ansible-playbook -i 'localhost,' -c local zim2.opt.pb \
  -e USERMODE=True -e BINS_RUN_BYPASS=True -e SYSTEMD_THUNK_BYPASS=True
ansible-playbook -i 'localhost,' -c local mise2.opt.pb \
  -e USERMODE=True -e BINS_RUN_BYPASS=True -e SYSTEMD_THUNK_BYPASS=True
```

Host prerequisites here were already installed: Node 26, Zsh, Mise,
`block-in-file`, Git, and Zim's declared Debian packages. `USERMODE` skips
render-time package installs, but the generated bare `install.sh` still includes
privileged package lanes. Use the focused host installer below, or explicitly
set `COMPFUZOR_APTLANE_BYPASS=1 COMPFUZOR_ARCHLANE_BYPASS=1` on the aggregate.
`COMPFUZOR_APT_BYPASS` is **not** that runtime lane's bypass name.

```sh
cd ~
host=$HOME/.local/opt/zim2-main
# Fresh-host prerequisite: registry currently points at canonical etc/zimrc.
"$host/bin/config-assemble.sh" --context canonical
"$host/bin/install-zim.sh"
ZIM_HOST_DIR="$host" "$HOME/.local/opt/mise2-main/bin/install-user.sh"
```

Mise2 now contributes `10-mise2-config.conf` in **zimenv**, before zim-mise's
phase 20 activation. It selects `$HOME/.config/mise2/config`, honoring explicit
`MISE_CONFIG_DIR` and then `MISE2_CONFIG_DIR`. Bash activation blocks select the
same config. Data/cache roots remain Mise's ordinary per-user roots.

For the OpenCode source-playbook contribution rehearsal, use these extra vars
for **both** source playbooks:

```json
{
  "USERMODE": true,
  "REPO_BYPASS": true, "GIT_BYPASS": true,
  "BINS_RUN_BYPASS": true, "GLOBAL_BINS_BYPASS": true,
  "LINKS_BYPASS": true,
  "SYSTEMD_INSTALL_BYPASS": true, "SYSTEMD_THUNK_BYPASS": true,
  "OPENCODE_BUS_PROXY_DISCOVERY": true
}
```

This renders configs/bins, without fetching/building source or activating units.
Then import both Zim contributions:

```sh
ZIM_HOST_DIR="$HOME/.local/opt/zim2-main" \
  "$HOME/src/opencode-git/bin/install-zim-user.sh"
ZIM_HOST_DIR="$HOME/.local/opt/zim2-main" \
  "$HOME/src/opencode-bus-proxy-git/bin/install-zim-user.sh"
```

The `ZIM_HOST_DIR` override is important: the legacy importer defaults to
`~/.config/zsh/zimfw.conf` and `/opt/zim-main`, whereas this host uses
`~/.config/zsh/zim2/zimfw.conf` and `~/.local/opt/zim2-main`.

## Local profile choices and residual weaknesses

- The full roster cloned successfully. `atuin`, `bd`, `helm`, `jj`, `kubectl`
  and `timoni` global installs are inaccessible to the fresh account. Their
  Zim modules used command-table presence rather than successful executable
  access; some cached empty completion files and misleading success messages.
  This profile disables **k, zim-atuin, zim-atuin-session, zim-beads, zim-helm,
  zim-jujutsu, zim-kubectl, zim-timoni** via consumer-local CONFIG membership.
  Those choices survived reinstallation. Re-enable after accessible tools are
  provisioned, using `config-inputs.sh enable zimrc/zimrc 55-<name>.conf` and
  rebuilding Zim. No host-wide module roster was reduced.
- `zim-opencode` was repaired in its own repository at **`3cf161b2`**:
  V2 completion flag, executable check, directory creation, atomic publication,
  failure preservation, and retry of an empty cache. Nine mock tests passed.
  Its `init.zsh` was explicitly copied into the target's cloned module for this
  rehearsal. **Publication is pending**; a new clone on deck will not inherit
  that local patch until it is shipped or deliberately copied.
- Fresh install initially failed its final registry link because the canonical
  config had never been assembled. The explicit canonical assembly above
  resolves it. The host locator still depends on a config artifact and old
  path-discovery conventions; the newer advertised registry does not yet replace
  this [explicit import bridge](/doc/config/consumer-toolkit.md#zim-complete-installation).
- A templated value inside `ZIM_MODULES.env` remained literal Jinja even with
  `resolve`. Mise2 uses a normal templated local source module instead. Recursive
  declaration rendering remains a separate generator weakness.
- Run login probes with HOME cwd and a PTY: sudo's `-H` alone does not change cwd.
  Inheriting the operator's cwd made Mise discover the operator's ancestor
  `.tool-versions`; running interactive Zsh without a terminal produced ZLE
  option errors unrelated to real terminal startup.
- The native runtime flags on zim2/mise2 do not prove every aggregate path is
  native. Rendered install paths still include legacy package/user composers.

## Landed improvements and checks

| Change | Check / checkpoint |
|---|---|
| Bounded reserved-band allocation, existing-account checks, validated atomic sudoers installation | `b4cbfdd8`; six rendered mock-NSS tests; live existing-account rerun retained UID 61019 |
| Correct named-group ID return in permission helper | `3ab3ea69`; focused tests; independently found, not the root-owned-staging cause |
| Shared block-in-file deployment traversal (`DIRMODE: 0755`) | `23428943`; syntax check; live root mode applied, target executes standalone |
| Mise2 shell config alignment | `6770d8b0`; rendered cache regression plus Zsh default/override assertions; live shell setting is pnpm |
| Zim fragment compiler | 81 checks passed |
| Live account probe, including native CLI explicit API call | All checks passed after rerender and reinstall |
| Corrected proxy-owned Zim routing | Fresh shell reaches `/_bus/health` with plain `opencode api get`, no explicit server flag; shell/status/HTTP checks pass |
| Proxy routing regression | Four real proxy render modes pass; default/custom ports, preserved caller defaults, no wrapper; both source-playbook syntax checks pass |
| Aggregate Zim and Mise status | Both exit 0 |

The broader discovery fixture's **origin** render is currently blocked by
`SUBSYSTEM` eager materialization encountering undefined `NPM` in
`vars/common.yaml`; a diagnostic empty NPM override proceeded to a separate
`apply-patches.sh` Jinja comment-tag error. Those shared-generator faults were
not changed here. The proxy regression is independently runnable, and the live
account's origin contribution was successfully rendered from its earlier source
snapshot during the initial rehearsal.

Exploratory logs are under `.test-agent/zimtest-integration/` in the operator
checkout. They are local scratch, not portable evidence dependencies.

## Cleanup and deck landing

Removed one confirmed dangling fixture link: `/opt/opencode-dev` pointed at the
absent `/tmp/compfuzor-opencode-instances-93oejw6g/src/opencode-dev`; no user unit
referenced it. Broader cleanup follows the OpenCode integration:

- `/usr/local/bin/opencode` is the running binary, byte-identical to the
  `opencode-202610110425` snapshot; retain these as the live/rollback pair.
- `opencode-202609300301` is another explicit dated snapshot, not automatically
  disposable. Global helper links still point into `/usr/local/src/opencode-git`.
- The old `opencode-cleanup.timer` is **active**, and its service remains linked.
  Current source names `opencode-cleanup-tmp.*`; reconcile deliberately during
  deployment rather than deleting an active timer as junk.
- Manager/auth/skills deployments also exist. Their age alone does not establish
  non-use. Their consumers were not audited in this rehearsal.

For **deck**, first choose whether the new account owns a local server/proxy or
connects to an existing deployment. `127.0.0.1:49372` means deck itself there.
Provision accessible prerequisites and the corrected zim-opencode module; carry
the explicit host/import sequence and account smoke test. Remote Ansible's
controller-side permission heuristics remain a limitation: running locally as
the target account is the proven route. A local server also needs the composed
OpenCode build, proxy build, correct user service credential and watcher setup;
the render-only producer rehearsal does not supply those.
