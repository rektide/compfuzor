---
type: ImplementationCheckpoint
title: Offline dial precision producer and TCP relay
description: First coherent implementation slice, protocol proof, toggle boundaries, and proposed main/service integration awaiting architectural approval.
resource: /design/kanata-dial/implementation0.gpt61sm.md
status: draft
generated: { by: model:gpt-6.1-sol-medium, at: 2026-10-07 }
sources:
  - resource: /design/kanata-dial/brief0.gpt61s.md
    title: User authorization and first-slice gate
  - resource: https://github.com/jtroo/kanata/blob/2f84d17/tcp_protocol/src/lib.rs
    title: Installed protocol message spelling
  - resource: https://github.com/jtroo/kanata/blob/2f84d17/src/tcp_server.rs
    title: Initial snapshot, fake-key mutation, and missing successful action acknowledgement
  - resource: https://github.com/systemd/systemd/blob/main/man/systemd.unit.xml
    title: JoinsNamespaceOf semantics
  - resource: https://github.com/systemd/systemd/blob/main/man/systemd.exec.xml
    title: Shared private network namespaces
---

# Situation and scope

The [brief](/design/kanata-dial/brief0.gpt61s.md) requests a separately
toggleable media enhancement and a real keyboard→dial TCP control path,
without changing Surface Dial or deploying live input/network changes. This
checkpoint implements that first offline slice. No other current research wave
was read. Existing user-authored media `.03/.01` actions remain untouched.

## Delivered

- [`kanata-dial.etc.pb`](/kanata-dial.etc.pb): inert config/relay assets plus
  producer group **kanata-dial**, explicit order **110** (after default media
  order 100). No units, system links, install execution, membership publication,
  compositor reload or daemon start is authored here.
- [`dial.kbd`](/files/kanata-dial/dial.kbd): exact raw device include, distinctive
  `kanata-surface-dial` output, raw `lsft` suppressed, base `S-volu/S-vold`,
  virtual `precision-hold` selects precision `f23/f24`.
- [`relay.ts`](/files/kanata-dial/relay.ts): two independently reconnecting TCP
  sessions; initial and subsequent keyboard layers select a held bit; source
  disconnect/unknown layer releases it; every target connection checks the key
  name and sends Release before optional Press. Duplicate state does not press
  twice. Periodic current-layer queries bound silent-peer liveness.
- [`protocol.ts`](/files/kanata-dial/protocol.ts): newline JSON, fragmented and
  multiple frames, maximum 64 KiB frame, invalid/oversized frames disconnect.
  Outbound backpressure disconnects rather than retaining an unbounded queue.
- [`cli.ts`](/files/kanata-dial/cli.ts): explicit source/target ports through
  environment, loopback hosts only, graceful signal cleanup; target-only
  `--reset` for stop/recovery. Dependency-free native TypeScript execution.
- [`keyboard-signal.example.kbd`](/files/kanata-dial/keyboard-signal.example.kbd):
  parser-checked **example**, not a replacement main config.

The contribution owns new action IDs, not patches to media actions. Plain and
Shift F23/F24 both invoke configurable extra precision (candidate `0.005`).
The TCP-controlled vocabulary is therefore consequential: ordinary dial volume
remains legacy Shift+Volume (`0.01`), while keyboard precision selects F keys.
Merely emitting F keys in both layers would make this relay redundant with the
compositor's physical keyboard Shift handling.

# Verified protocol and limits

Source was inspected first at `~/archive/jtroo/kanata`:
[server acceptance](https://github.com/jtroo/kanata/blob/2f84d17/src/tcp_server.rs#L149-L164)
publishes an initial `LayerChange`;
[fake-key handling](https://github.com/jtroo/kanata/blob/2f84d17/src/tcp_server.rs#L229-L260)
mutates the layout and returns **no successful action acknowledgement**. Unknown
virtual-key names produce `Error`. The relay uses real `ActOnFakeKey` Press and
Release, not an invented mutable-variable API.

The reset helper discovers the named key, sends Release, then requests current
layer on the same stream. A reply establishes **command-dispatch ordering**,
not final processing/output completion. TCP client disappearance is not a lease:
the server does not track per-client fake-key ownership. There must be exactly
one owner of `precision-hold`; concurrent clients can invalidate these guarantees.

Reconnect clears stale target hold before using the current source snapshot.
Graceful stop releases on the existing connection and independently attempts a
target reset; reset failures propagate. Abrupt SIGKILL cannot execute cleanup.
Reset-on-restart and a future `ExecStopPost=… --reset` are recovery mechanisms,
not a guarantee of no transient held state between crash and recovery. If reset
cannot reach the target, **stop the dial instance before removing F bindings**.

The source adapter supports one effective-layer snapshot, not independently
queryable physical modifiers. Any unknown/other layer means release. A future
layer stack can hide held precision; semantic pushes alone would instead lack a
reconnect snapshot. This limitation is deliberate and must not be advertised as
a generic keyboard state publisher.

# Exact main configuration proposal — not applied

Preserve the actual selected main config's entire `defcfg` device/body semantics
and caps tap-hold, including the authored/live Kinesis drift. Add raw/output
exclusions to that actual owner:

```lisp
"Surface Dial Virtual Keyboard/Mouse"
"kanata-surface-dial"
```

Extend its `defsrc` with `lsft rsft`. In base, map each to
`(multi lsft (layer-while-held dial-precision))` / equivalent `rsft`. Add the
all-transparent `dial-precision` layer. Both modifiers continue producing their
normal OS Shift; caps keeps `(tap-hold 100 100 esc lctl)` through transparency.
The [example](/files/kanata-dial/keyboard-signal.example.kbd) validates syntax,
not simultaneous-Shift or caps timing behavior on hardware. Do not adopt kinata
or add its Kinesis exclusion merely to implement this signal.

Proposed explicit private IPv4 endpoints (allocation pending approval): main
`--port 127.0.0.1:5828`, dial `--port 127.0.0.1:5829`; relay environment
`KANATA_KEYBOARD_PORT=5828`, `KANATA_DIAL_PORT=5829`. Upstream CLI accepts full
IP:PORT, avoiding implicit wildcard binding.

# Exact namespace/service proposal — not emitted

[PrivateNetwork](https://github.com/systemd/systemd/blob/main/man/systemd.exec.xml)
creates loopback-only networking; [JoinsNamespaceOf](https://github.com/systemd/systemd/blob/main/man/systemd.unit.xml)
requires private namespace settings on both participants. Multiple already
running listed units with different namespaces are ambiguous. Join one anchor.

Preferred lifecycle shape for review:

1. A non-input `kanata-network.service` anchor (`PrivateNetwork=true`, long-lived
   inert process) owns stable namespace lifetime independently of keyboard/dial
   restarts. Alternatively use canonical main as anchor, but require coherent
   restart ordering and verify namespace survival/rejoining behavior.
2. Main, dial and relay set `PrivateNetwork=true` and
   `JoinsNamespaceOf=kanata-network.service`, with explicit Requires/After for
   the anchor. Retain the device/input and other sandbox restrictions.
3. For TCP participants replace the existing impossible address-family list
   with narrowly admitted `AF_INET` (plus required `AF_UNIX`); retain
   `IPAddressDeny=any` and allow only `127.0.0.1/32`. Parent must verify inherited
   restrictions, seccomp and namespace interactions before selecting final units.
4. Dial consumes the existing `_kanata` identity/uinput rule and source binary;
   it must not redeclare the account. Its unit binds the staged config read-only
   and has no alias to canonical `kanata.service`.
5. Relay requires no input devices, input-group membership or uinput binding.
   Order After dial so reverse stop ordering runs relay reset while dial is alive.
   Proposed `Restart=on-failure`, bounded `ExecStopPost=node …/cli.ts --reset`,
   and stop timeout exceeding reset's 5 s deadline. The stop hook shares its
   unit namespace. Node's executable-memory requirements need explicit review:
   consider `--jitless --no-expose-wasm` before weakening MemoryDenyWriteExecute.

This playbook currently follows media's home-local material placement. A hardened
system input service **cannot simply execute that home-local path** under
`ProtectHome=true` or assume `_kanata` traversal. The next service slice needs
an explicit system-readable artifact root (shared `PREFIX_DIR`, deliberate
copy/install, or separate service owner). Do not silently move the user's producer
material or loosen ProtectHome. Keep user membership and system service installs
distinct action audiences and transaction boundaries.

# Toggle contract and rollback

The whole extension bit and momentary precision bit are different.

**ON:** validate/install or enable the producer in every intended receiver;
explicitly apply compositor configuration; ensure scoped dial/main topology
is safely installed; only then start relay. Failure before relay start leaves
legacy fallback. Keep media's group enabled throughout.

**OFF:** stop relay and prevent restart; require successful namespace-local reset
(or stop dial instance); only then disable `kanata-dial` membership and explicitly
apply compositor configuration. Leaving the dial remapper running in base keeps
Shift+Volume fallback. If removing the remapper too, stop it before relinquishing
the raw exclusion to main, with a reviewed grab-ownership handoff.

CONFIG membership/output rollback does **not** roll back systemd state or a
compositor reload. Receiver failures can leave partial per-receiver enablement;
do not start relay until all intended consumers are ready. An OFF failure before
reset must retain F bindings. An OFF failure after reset can leave dormant F
bindings, which is safer than unbound live precision events. No pruning is added.

Current generator inspection revealed the older producer guide's per-target
script description no longer matches this checkout: actual producer output is
`install-keybindings.sh` (`install-offer`) plus receiver-selection/registration
material. This slice follows that generator and does not refactor it. Selection
and any explicit registry admission remain deliberate install-time operations.

# Other dial modes and evidence boundary

Surface Dial source inspected at managed `/usr/local/src/surface-dial-git`:
only Volume and Media+Volume synthesize Shift; mute/transport use their plain keys;
[Zoom](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/controller/controls/zoom.rs)
uses Ctrl+Equal/Minus, not Shift. These keys are not remapped here; the separate
touchpad is not included. Physical keyboard modifiers still affect compositor
matching, including existing Zoom limitations.

Linux [event handling](https://github.com/jtroo/kanata/blob/2f84d17/src/kanata/linux.rs#L57-L104)
passes non-key events and processes unmapped keys through the mapping engine;
[scroll handling](https://github.com/jtroo/kanata/blob/2f84d17/src/kanata/linux.rs#L160-L209)
normalizes low/high-resolution wheel pairs. Therefore wheel preservation is
**intent, not byte-exact passthrough proof**: batch pairing/counts, reconnect,
key capability advertising, Zoom and mute/transport timing require authorized
manual checks before deployment. No daemon actuation or source patch is included.

# Offline checks and next gate

Passed:

- `pnpm exec vitest run tests/kanata-dial`: 10 tests, mock TCP lifecycle and pure
  compilation to both native binding forms; base actions remain `.03/.01`.
- `pnpm exec tsgo -p tests/kanata-dial/tsconfig.json --noEmit`.
- `pnpm exec vp lint files/kanata-dial tests/kanata-dial`.
- `python tests/kanata-dial/render.test.py`: isolated real Ansible render,
  configurable step override, exact source transport, executable CLI, 4 resources,
  separate group/order, no units or membership publication, protected owners
  unchanged, both generated configs accepted by installed Kanata `--check`.
- Syntax-only installed Kanata checks of source configs also passed.

Tests create only ephemeral mock TCP endpoints, never real input listeners.
Scratch roots are isolated under `.test-agent/kanata-dial`; no live ports,
unit operations, input grabs/injection, sudo, /etc-/srv-/usr-writes or reloads ran.

Next gate: parent reviews code and picks signal/namespace/artifact ownership,
F23/F24 allocation and amount policy. Only then implement one coherent service
artifact + main-owner integration slice, with isolated render checks. Remaining
questions: dedicated namespace anchor vs main anchor; desired system material
location; whether this main instance is the complete designated keyboard signal
source; physical dual-Shift/caps behavior; intended active receivers and explicit
application/reload procedure. No live deployment is authorized by this checkpoint.

# Cross-references

- [Dial remapping assessment](/design/surface-dial-layers/dial-remap0.gpt61s.md):
  device-scoped capture requirement; this implementation changes its earlier
  always-F-key proposal to legacy fallback + TCP-selected F keys.
- [TCP assessment](/design/surface-dial-layers/tcp-scheme0.gpt61s.md): real wire
  protocol and effective-layer snapshot limits; Surface Dial stays unchanged.
- [Kanata owner guide](/doc/input/kanata.md): shared binary/identity, sandbox and
  current authored/live device topology drift that the next slice must preserve.
- [Producer guide](/doc/config/keybinding-producers.md): separate membership and
  ordering, with the current generator-interface drift noted above.
- [Consumer guide](/doc/config/keybinding-consumers.md): CONFIG publication
  boundary does not extend to services or compositor reloads.
- [Domain README](/files/kanata-dial/README.md), [TCP tests](/tests/kanata-dial/relay.test.ts),
  [contribution test](/tests/kanata-dial/producer.test.ts), and
  [isolated render test](/tests/kanata-dial/render.test.py): implementation evidence.
