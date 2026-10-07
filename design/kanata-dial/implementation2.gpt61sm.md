---
type: ImplementationCheckpoint
title: Completed offline Kanata dial integration and enhancement toggle
description: Generated private-network units, copied system runtime, optional main publisher, final 0.003 precision policy and ordered ON/OFF controls awaiting deployment review.
resource: /design/kanata-dial/implementation2.gpt61sm.md
status: draft
generated: { by: model:gpt-6.1-sol-medium, at: 2026-10-07 }
sources:
  - resource: /design/kanata-dial/implementation1.gpt61sm.md
    title: Saved runtime/reset safety correction
  - resource: /kanata-dial.etc.pb
    title: Producer, copied assets, multi-unit declarations and scoped action contribution
  - resource: /kanata.srv.pb
    title: Main-owned optional signal, capture exclusions and private TCP integration
  - resource: /skill/systemd.md
    title: Native multi-unit/copy installation and inert enable/start controls
  - resource: /files/kanata-dial/toggle.ts
    title: Explicit membership/service/compositor orchestration
---

# Destination and review gate

This follows the parent's review of the [initial slice](/design/kanata-dial/implementation0.gpt61sm.md)
and [reset/runtime correction](/design/kanata-dial/implementation1.gpt61sm.md).
The human's final precision amount is **0.003**, not 0.0003 or 0.005. F23/F24
are allocated to this contribution's directions. **OFF disables enhancement
only**, keeping legacy dial volume available. The independent device-ID inquiry
is parked; no current wave output from it was read.

Implementation is complete through the **offline artifact/toggle gate**. No live
deployment, listener, namespace creation, device grab/injection, service operation,
compositor application or privileged filesystem change was performed. Parent
review of these interfaces and evidence still precedes any deployment.

# Concrete generated interfaces

[`kanata-dial.etc.pb`](/kanata-dial.etc.pb) keeps home-local producer material
and existing action audiences rather than moving it into a system service tree:

| Entry/material | Ownership and effect on explicit invocation |
|---|---|
| `bin/install-user.mjs` / default `install.mjs` | Existing producer receiver-selection/registry install; no input-service activation. |
| `bin/install-system.mjs` | Create public system runtime directory; copy runtime and unit files using existing LINKS/systemd copy strategies; daemon-reload, **no enable/start**. |
| `bin/apply-user.mjs` / default `apply.mjs` | Enhancement `on|off` with explicit receiver profiles and compositor apply hook. No system-audience apply alias is fabricated. |
| `kanata-dial/{protocol,relay,cli,toggle}.ts` | Dependency-free native TypeScript; source and generated material can be read independently. |
| `keybinding-producer.json` | Producer `kanata-dial`, order 110, four resources, separate from base media membership. |
| `links.json` | Four runtime copy-only records plus native systemd unit-copy records; rendering only packages this plan. |

The user-default install family is not an all-audiences service installer. The
system install is explicit. Existing CONFIG ownership/transactions remain intact;
there is no new JSON state store, bespoke staging reflection, runtime refactor or
cross-audience transaction claim.

System runtime is **`/etc/opt/kanata-dial-main`**, deliberately copied, not a link
into HOME. Directory mode 0755, `dial.kbd` and all runtime `.ts` files mode 0644.
The source CLI is executable, but the deployed TS files are invoked through the
public **`/usr/bin/node`**. Scratch-root overrides test the same interface without
applying system destinations. System units use `SYSTEMD_INSTALL_STRATEGY=copy`,
`SYSTEMD_ENABLE=false`, `SYSTEMD_START=false`, and no alias to canonical main.

## Generated units

| Unit | Role and boundary |
|---|---|
| `kanata-dial-network.service` | Stable non-input loopback namespace; sleep process, DynamicUser, PrivateNetwork, PrivateTmp=false, no input/uinput permissions, Restart=no. |
| `kanata-dial.service` | Dedicated raw dial capture; existing `_kanata`/input identity and `/usr/local/bin/kanata`; `127.0.0.1:5829`; retains input sandbox including MDWE. |
| `kanata-dial-relay.service` | DynamicUser, no input group/device binds, `/usr/bin/node …/cli.ts`; source 5828 → target 5829; on-failure restart, 15 s stop limit, `ExecStopPost=… --reset`. |
| `kanata-dial-reset.service` | Namespace-local one-shot target reset with observed fallback requirement; no dial Requires dependency that would inadvertently start a stopped dial during OFF. |

Main/dial/relay/reset require and order after the one anchor, bind their lifecycle
to it and use `PrivateNetwork=true`, `JoinsNamespaceOf=kanata-dial-network.service`.
Participants allow only AF_INET plus AF_UNIX and `127.0.0.1/32`; IPAddressDeny=any
remains. Main/dial retain their other network/device/kernel/filesystem protections.
The anchor's PrivateTmp=false means it does **not** cause participant tmp sharing.

Only relay/reset use `MemoryDenyWriteExecute=false`. Parent's actual system Node
26.10.0 proof showed `--jitless` breaks native TS's Amaro WebAssembly, and
`--no-expose-wasm` is not a supported Node option. The actual plain system Node
CLI and copied-runtime import are tested. No input unit is dehardened for Node.

## Namespace lifetime and failure

- Anchor lifetime is independent of ordinary main/dial/relay process restarts.
  Restarting a participant joins the existing anchor rather than creating a new
  network island. Requires/After ensure the anchor is running before join.
- Anchor failure stops bound participants. It deliberately does not auto-restart
  and silently replace its namespace while old participants survive. Repair and
  explicitly run approved ON to restore the dependency chain.
- Stopping/restarting main can stop dependent dial/relay; automatic restoration
  of all input services is not inferred from producer membership. ON starts dial,
  whose Requires starts main/anchor if needed, then explicitly starts relay only
  after consumers are ready.
- After ordering makes reverse stop order reset relay while the dial is still
  available. StopPost failure remains visible. OFF additionally invokes the reset
  one-shot and requires success; it does not trust service stop alone.
- TCP disconnect is not a held-key lease. SIGKILL recovery relies on StopPost
  and reset-before-apply on relay restart. No no-transient-crash-state guarantee
  is claimed. Exactly one relay/controller and one toggle invocation may own this
  domain; arbitrary extra TCP clients are outside the contract.

# Main owns the optional publisher

[`kanata.srv.pb`](/kanata.srv.pb) now has default-OFF **`KANATA_DIAL_ENABLED`**.
OFF renders the predecessor config body byte-for-byte and retains old no-listener
unit protections, caps behavior and authored exclusion defaults. BlueTurn/Kinata
playbooks and base media playbook were not changed.

ON adds raw `Surface Dial Virtual Keyboard/Mouse` and normalized
`kanata-surface-dial` exclusions, maps physical `lsft`/`rsft` to normal Shift plus
transparent momentary `dial-precision`, and publishes on private IPv4 port 5828.
Caps remains `(tap-hold 100 100 esc lctl)` through layer transparency. Both Shift
outputs remain normal keyboard modifiers; the TCP layer selects the extra-fine
F-key vocabulary in the isolated dial instance.

`KANATA_DEV_NAMES_EXCLUDE` defaults to the prior authored BlueTurn + Kinesis list.
An operator retaining current live BlueTurn-only topology must explicitly supply
that list; there is no implicit kinata adoption/removal. `KANATA_CONFIG_PRESERVE`
still leaves existing config bytes untouched even when integration flags differ.

Dial startup checks **both** the enabled config marker and main's optional
current-invocation `RuntimeDirectory=kanata-dial-publisher`. Thus merely installing
an enabled config while the old main process still runs cannot authorize a dial
grab. This is an invocation/artifact fence, not hardware event verification;
main must be deliberately installed and restarted before the first activation.
A preserving render with old config correctly leaves dial startup fenced out.

One effective layer is still only one effective-layer snapshot: future keyboard
layers can hide physical Shift state. Other excluded keyboard instances do not
contribute to this publisher. This first adapter is not a general multi-instance
modifier aggregator. No device-conditioned Linux mapping patch is introduced.

# Whole-enhancement ON/OFF

The generated user apply leaf executes [`toggle.ts`](/files/kanata-dial/toggle.ts).
Explicit receiver profiles avoid hidden discovery or assumptions about which
compositor is currently intended. The low-level existing `keybindings.mjs`
`install`, `enable` and `disable` commands are used with explicit target/profile/
context/user scope, not hand-authored membership files. The normal generated
install offer/registry mechanism remains independently available.

Illustrative **post-approval** invocation, not executed here:

```sh
material="${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/kanata-dial-main"
"$material/bin/apply-user.mjs" on \
  --niri-profile /absolute/niri/keybinding-niri.json \
  --umbriel-profile /absolute/umbriel/keybinding-umbriel.json \
  --apply-command /absolute/operator-selected-apply-hook
```

`--context` defaults to user. At least one receiver and an explicit absolute
apply hook are required before any effects. The hook is the operator's deliberate
configuration application/readiness gate; there is no automatic reload default.
It receives `on|off` followed by each selected `--TARGET-profile PATH` and
`--TARGET-context ID`. On ON its success must mean both precision directions,
plain and Shift, are active in every intended compositor. Membership enable
deliberately preserves individually disabled binding slots and edited native
placements; successful CONFIG publication alone cannot prove those bindings are
active. This implementation does not silently overwrite those user choices or
invent a generic runtime inventory API. A missing/insufficient readiness hook
remains a deployment blocker. Source development
can use `node files/kanata-dial/toggle.ts … --material /absolute/rendered-material`.

The toggle invokes **`sudo -n /usr/bin/systemctl`** for its explicit unit actions.
This is not a privilege broker: noninteractive authority must be separately
approved, and service installation remains a distinct system action. Tests inject
a command runner and never invoke actual systemctl/sudo. Commands have bounded
30 s child-process deadlines; CONFIG retains its own validation/rollback behavior.

## ON

1. Stop any existing relay; start scoped dial (which checks main handoff).
2. Disable/stop relay with `disable --now`, then observe reset/fallback via the
   namespace-local reset unit.
3. For each explicit receiver, install producer resources and enable its group.
4. Run the explicit apply hook. **All selected receivers must succeed first.**
5. Start relay. No automatic boot enablement is inferred.

Receiver/hook/start failure attempts stop/reset recovery; reset failure stops
dial as fail-safe. Partial receiver membership can remain after failure, but the
relay is not knowingly left running against an unready receiver. No false rollback
of successful earlier receivers or compositor effects is claimed.

## OFF (enhancement only)

1. `disable --now` relay, preventing on-failure and prior hand-enabled boot restart.
2. Start reset one-shot; require actual observed fallback `base` within its bound.
3. Only after success, disable the `kanata-dial` group in each explicit receiver.
4. Run the explicit apply hook. Dial and anchor stay running in legacy fallback.

Reset/stop failure stops dial as fail-safe and **retains F bindings**. If fail-safe
stop also fails, the error reports both failures and still does not disable them.
Failure after successful reset may leave dormant/partially disabled bindings;
this is safer than active precision events without bindings. Keep media's base
group enabled. Never substitute direct membership disable for this safety ordering
while relay can still hold precision. An apply hook's actual correctness is the
operator's responsibility, not something a successful arbitrary command proves.

# Wire safety and remaining behavior limits

`ActOnFakeKey` has no successful action ACK and enqueues layout events. Release
followed immediately by a query can report stale precision. Both startup and
explicit reset now discover the key, Release, and poll until **CurrentLayerName
equals configured fallback**. Wrong/malformed/unresponsive layer fails closed.
The target is not ready to reapply source hold until fallback is observed.
This is effective-layer proof, not a guarantee every OS output event has drained.

Bounded framing, independent retries, source loss/unknown-state release, duplicate
hold suppression, finite deadlines, backpressure reconnect, and clean stop remain.
Actual system Node native TS execution is verified; parameter properties were
removed and domain typechecks require erasable syntax.

Mute/media transport and Ctrl+Equal/Minus Zoom remain unmapped by the dial map;
wheel handling follows upstream's low/high-resolution normalization, not a claim
of byte-exact passthrough. Physical dual-Shift/caps feel, reconnect event counts,
wheel pairs, Zoom, mute/transport, compositor matching under extra modifiers,
and F-key collisions across the full live producer graph remain deployment/manual
acceptance checks. No new media daemon actuation or Surface Dial source change.

# Offline evidence

The domain suite covers mock TCP lifecycle, delayed fallback processing, stuck
reset rejection, actual system Node mock CLI, pure native binding compilation,
whole-toggle success/failure ordering and early selection rejection. The real
Ansible render test redirects PREFIX/SRVS/ETCS/runtime roots, bypasses all execution,
checks multi-unit sandbox/copy/action plans, exercises **only scratch runtime asset
copy records**, imports the copied CLI with system Node, parser-checks dial/example/
enabled main, compares default main bytes against the predecessor fixture, verifies
explicit BlueTurn-only topology and preserving rerender, and statically verifies
generated units. Unit destinations are never applied.

The existing source-service regression suite also passed after the optional main
change: default unit hardening, one shared identity declaration, no Debian package
dependency, preserved keymap/config flag behavior, and its live artifact/account
fence all remained intact. Exact final command results are recorded in the parent
checkpoint response; no existing research/manual result is promoted to live proof.

# Cross-references

- [Previous runtime correction](/design/kanata-dial/implementation1.gpt61sm.md):
  why dispatch ordering alone was insufficient and native TS parameter properties
  were replaced; saved before integration changes.
- [Domain README](/files/kanata-dial/README.md): concise executable/source entry map.
- [Relay tests](/tests/kanata-dial/relay.test.ts), [toggle tests](/tests/kanata-dial/toggle.test.ts),
  [producer tests](/tests/kanata-dial/producer.test.ts), and [render test](/tests/kanata-dial/render.test.py):
  mock/pure/isolated evidence, not live input or network validation.
- [Default config fixture](/tests/kanata-dial/fixtures/main-default.kbd): previous
  authored bytes used to fence default-OFF behavior.
- [Existing source-service tests](/tests/integration/kanata_source_services.test.py)
  and [Kanata owner guide](/doc/input/kanata.md): account, binary and current live
  versus authored topology remain with their existing owners.
- [Keybinding producer](/doc/config/keybinding-producers.md) and
  [consumer](/doc/config/keybinding-consumers.md) guides: durable separate group and
  CONFIG publication boundaries; generator's newer install-offer interface differs
  from older guide script names as noted in the first checkpoint.
