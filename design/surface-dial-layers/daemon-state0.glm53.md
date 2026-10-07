---
type: ArchitectureAssessment
title: Surface Dial daemon-owned precision state and sideways control channel
description: Source-verified daemon architecture, the absence of any live-control facility today, and a coherent fork between compositor-side key discrimination and daemon-owned action selection with a proposed sideways state protocol.
resource: /design/surface-dial-layers/daemon-state0.glm53.md
status: draft
generated: { by: model:glm53, at: 2026-10-06 }
stale_after: 2027-01-06
sources:
  - resource: /home/rektide/src/surface-dial-layered
    title: Compfuzor-managed daemon workspace (upstream 43dd973 content plus discovery docs)
  - resource: /home/rektide/src/surface-dial-linux
    title: rektide fork carrying four local commits beyond upstream 43dd973
  - resource: /design/surface-dial-layers/brief0.gpt61s.md
    title: Wave brief for precision layers and sideways modifier state
  - resource: /design/surface-dial-input/assessment0.gpt61s.md
    title: Verified Umbriel cross-keyboard modifier aggregation and dial chord evidence
  - resource: /design/surface-dial-input/kanata-assessment0.gpt61s.md
    title: Kanata merger capability and modifier-collision source evidence
  - resource: /design/surface-dial/diagnosis0.glm53.md
    title: Prior end-to-end dial chord diagnosis
  - resource: /surface-dial.src.pb
    title: Declared daemon deployment (source build, user service)
  - resource: /media-keys.etc.pb
    title: Declared coarse 0.06 / fine 0.02 media actions
---

# Daemon-owned precision state and a sideways control channel

## Stage setting

The wave brief reframes this from a bug hunt into a behavior inquiry: the
existing fine adjustment likely works; the new desires are a significantly
smaller normal dial step, a reduced normal/finer ratio, and an additional
even-finer level when **physical keyboard Shift is held**. The stock daemon
already emits its own synthetic Left Shift with every volume tick, so the new
modality cannot ride on the Shift modifier bit as-is — physical and synthetic
Shift must remain distinguishable.

This document covers the daemon side only: source architecture, control and
mode selection, existing (nonexistent) IPC and variable-update hooks, a
possible local sideways state channel, and daemon-side actions versus
emitting distinct keys. Compositor IPC capabilities and Umbriel/Kanata
publisher boundaries arrive from the parent's independent investigation and
are cited as parent-reported, not re-verified here. Unit/log/deployment
inspection belongs to another agent in this wave. No service, hardware,
config, or code changes were made; everything below is source reading.

## What the daemon is (source-verified)

Three source copies exist and diverge:

- `/home/rektide/src/surface-dial-layered` — jj workspace whose `src/` matches
  upstream `daniel5151/surface-dial-linux` at `43dd973` byte-for-byte in the
  files that matter here (`volume.rs`, `media_with_volume.rs`,
  `fake_input.rs`), plus compfuzor-generated material (`bin/`, `env`, `repo`)
  on an unmerged head and two state-discovery docs under `doc/discovery/`.
- `/home/rektide/src/surface-dial-linux` — rektide's fork (remote
  `github.com:rektide/surface-dial-linux`) at the same upstream commit plus
  four local commits (2025-12-11) adding a `--notification-timeout` clap
  flag threaded through `main.rs`, `config.rs`, and `controller/mod.rs`.
  Local daemon patching is therefore established practice, not a new fork.
- The declared deployment source is `/usr/local/src/surface-dial-git` per
  [`diagnosis0`](/design/surface-dial/diagnosis0.glm53.md); which tree feeds
  the running unit is deployment-G territory.

Architecture, per [`src/`](/home/rektide/src/surface-dial-layered/src) and
the pre-existing
[`config-control-state-reference.md`](/home/rektide/src/surface-dial-layered/doc/discovery/config-control-state-reference.md):

- **Event pipeline**: a udev-enumerating `EventsWorker` matches
  `Surface Dial System Multi Axis` and streams evdev events over mpsc into
  `DialDevice`, which synthesizes `ButtonLongPress` via a 750 ms timeout
  ([`dial_device/mod.rs:93-139`](/home/rektide/src/surface-dial-layered/src/dial_device/mod.rs#L93-L139)).
  Dial disconnect/reconnect is handled in-process: ENODEV breaks the read
  loop and the worker falls back to the udev monitor
  ([`events.rs:69-153`](/home/rektide/src/surface-dial-layered/src/dial_device/events.rs#L69-L153)).
  Reconnect does not require a daemon restart today.
- **Mode selection**: `DialController` dispatches to one of seven hardcoded
  `ControlMode`s (`main.rs:84-92`). Long-press enters `MetaMode`, a
  notification-backed menu rotated by the dial; selection persists one raw
  integer to `~/.config/com.prilik.surface-dial-daemon/config.txt`
  ([`config.rs:45-68`](/home/rektide/src/surface-dial-layered/src/config.rs#L45-L68)),
  read exactly once at startup
  ([`main.rs:77`](/home/rektide/src/surface-dial-layered/src/main.rs#L77)).
- **Action vocabulary**: each mode emits fixed chords through one shared
  uinput keyboard, `Surface Dial Virtual Keyboard/Mouse`
  ([`fake_input.rs:19-56`](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/fake_input.rs#L19-L56)).
  Volume and Media+Volume ticks emit
  `KEY_LEFTSHIFT + KEY_VOLUMEUP/DOWN`
  ([`volume.rs:36-48`](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/controller/controls/volume.rs#L36-L48));
  Zoom emits `KEY_LEFTCTRL + EQUAL/MINUS`. The synthetic modifier is
  hardwired per mode, not a daemon-wide layer.
- **Haptics is its own modality**: `set_mode(haptics, steps ≤ 3600)` pushes
  an HID feature report per mode
  ([`haptics.rs:89-109`](/home/rektide/src/surface-dial-layered/src/dial_device/haptics.rs#L89-L109)).
  Volume uses `steps: 36*2`. Tactile detent resolution is daemon-owned and
  fully independent of action step size — a finer baseline step wants a
  matching detent change, and that part needs no protocol at all.

A key detail of the virtual keyboard's **fixed capability set**: it
advertises LEFTSHIFT, LEFTCTRL, the media/transport keys, arrows, SPACE,
EQUAL, MINUS — and notably `KEY_LEFTCTRL` is advertised but unused by any
chord, while no F-region keys exist (nothing F13–F24). `key_press` /
`key_release` already handle arbitrary slices of advertised keys
([`fake_input.rs:149-183`](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/fake_input.rs#L149-L183)),
so any chord of currently-advertised keys is encodable today; adding F23/F24
is a two-line capability addition plus rebuild.

## Existing IPC, control protocols, variable-update hooks: none

This is the honest headline finding. Inventory of every external interface
the daemon has today:

| Interface | Direction | Mutability |
|---|---|---|
| Dial evdev node (`Multi Axis`) | in | read-only events |
| udev monitor | in | connect/disconnect only |
| uinput keyboard + touchpad | out | write-only injection |
| `notify-rust` notifications | out | display only |
| SIGINT/SIGTERM (`signal_hook`) | in | terminate only, no SIGHUP/reload semantics |
| `config.txt` | in (once) / out | read once at startup; written only by MetaMode |
| stderr → journal | out | logs |

There is no socket, no D-Bus, no stdin loop, no signal-based reload, and no
variable anyone can update while the daemon runs. The only live behavior
changes possible today are the ones the hardware itself offers (mode menu)
and dial reconnection. **Every "remote variable update" capability is
therefore a proposed protocol, not an existing facility** — the brief's
distinction between verified capability and proposal resolves entirely on
the proposal side here.

Also structural: the daemon reads only the dial's evdev node. It cannot see
physical keyboard Shift today *by construction*, and could not simply start
reading keyboards even if extended — kanata main holds exclusive grabs on
them (verified in the
[kanata assessment](/design/surface-dial-input/kanata-assessment0.gpt61s.md)).
Whoever publishes the physical-Shift bit must be an entity that already
legitimately sees those events.

## The central fork: where does the physical-Shift bit live?

The even-finer level needs one bit of information the daemon does not have.
There are exactly two credible homes for it, and they shape everything else.

### Path A — compositor-owned discrimination (no daemon state)

The daemon stops synthesizing Shift and emits keys the compositor can
discriminate using modifiers it already aggregates. Parent-verified boundary:
installed Umbriel's `Server::keyboardModifiers` ORs `wlr_keyboard_get_modifiers`
across all registered keyboards and `matchKeybind` requires mask equality
(cited with sources in
[`assessment0`](/design/surface-dial-input/assessment0.gpt61s.md)). Physical
Shift held on any keyboard therefore combines with a modifier-less dial key
at the matcher. Two encodings:

- **A1, plain media keys**: dial emits bare VOLUMEUP/DOWN; plain and
  Shift+plain bindings carry the two step sizes. Cheapest possible daemon
  change (delete `KEY_LEFTSHIFT` from two call sites). Rejected by the
  brief's own boundary: it redefines ordinary keyboards' volume keys, since
  bindings are not dial-scoped.
- **A2, reserved direction keys**: dial emits F24 for up, F23 for down
  (say); bindings become `F24` → fine, `Shift+F24` → even-finer. Ordinary
  keyboards are untouched; the dial's vocabulary becomes dial-private.
  Daemon cost: enable `KEY_F23`/`KEY_F24` on the uinput device, change two
  call sites, rebuild. Parent's keymap fixture (isolated libxkbcommon
  evdev/pc105/us) maps KEY_F23/F24 to F23/F24 plain and with Shift; a
  historical inet partial had touchpad mappings that later definitions
  override — the safe statement is that the *actual session keymap* must be
  checked, and the tested default works. Exact-key routing and binding
  authoring are the parent's producer domain.

Two structural wins A gets for free:

1. **The synthetic-Shift collision hazard disappears.** On the deployed
   single-kanata topology the dial's virtual keyboard and the physical
   keyboards flow through one merged output; the dial's Left Shift release
   can clear the merged coordinate while physical Shift is still held
   (source-evidenced in the
   [kanata assessment](/design/surface-dial-input/kanata-assessment0.gpt61s.md),
   not reproduced live). Removing the dial's Shift removes the hazard by
   construction, not just as a side effect of the new feature.
2. **Fail-safe by construction**: there is no held state anywhere. No
   lease, no expiry, no reconnect snapshot problem, no stale precision bit
   after a crash. The "held" semantics live exactly where they already
   work — the compositor's live modifier aggregation.

Limits of A: the modality vocabulary is whatever modifier masks can express
(Umbriel mask-equality means Shift+Ctrl is a *different* binding, not
"Shift plus more Shift"); each level consumes another key/modifier combo in
the global binding space; step magnitudes live in binding execs (fine —
`wpctl` args are arbitrary); and the daemon gains no per-mode step policy
or velocity behavior.

### Path B — daemon-owned action selection plus a sideways state channel

The daemon (or its emission policy) consults a precision bit fed from
outside. This is the richer axis and the one the brief most wants explored.

**B0 baseline**: daemon-owned fine steps with no channel at all. Replace
key emission in Volume mode with direct actuation (`wpctl set-volume
@DEFAULT_AUDIO_SINK@ <step>±`) using a config-declared step. Session
ownership works out: the unit is a user service
([`install/surface-dial.service`](/home/rektide/src/surface-dial-layered/install/surface-dial.service):
`WantedBy=default.target`, `ExecStart=%h/.cargo/bin/surface-dial-daemon`),
declared installed via `install-user.sh` in
[`surface-dial.src.pb`](/surface-dial.src.pb), and the media producer's
exec actions run with the same user audience
([`media-keys.etc.pb`](/media-keys.etc.pb), `ACTION_AUDIENCES: user`;
user-first is also the direction of the
[action-audiences inquiry](/design/action-audiences/intent0.gpt61sol.md)).
A user service inherits `XDG_RUNTIME_DIR` (PipeWire socket) and the session
bus (playerctl). B0 alone satisfies "smaller baseline, arbitrary ratio" —
but cannot express even-finer-on-physical-Shift, because the daemon still
does not know Shift is held.

**Who can publish the bit**: Umbriel cannot (parent: IPC families are
theme/overview/keyboard_layout/windows/workspaces/submap only; no modifier
or bind-executed events; modifier-only binds fire as release taps, not
held-state hooks). Direct observation of physical nodes is not a drop-in
either: kanata main holds exclusive evdev grabs, and a second reader on a
grabbed node receives no events. The credible publishers are kanata itself,
a watcher on an *ungrabged output* stream, or state sampling — details
below.

**Transport and publisher options** (B2 blocked, B4a partial — see
below):

1. **B1, daemon-owned Unix socket (proposed protocol).** An
   `AF_UNIX SOCK_DGRAM` (or SEQPACKET if replies are wanted) socket at
   `$XDG_RUNTIME_DIR/surface-dial/control.sock`. Same-user scope matches
   the unit and the producer's user audience; auth is directory
   permissions plus `SO_PEERCRED` uid checking; provenance is the peer
   that could only have reached the socket through the user's runtime dir.
   This is new daemon code but zero new system moving parts.
2. **B3, file-watched state** (`XDG_RUNTIME_DIR/surface-dial/precision`,
   inotify or read-at-dispatch). Simplest possible; weakest liveness and
   provenance; stale-state risk on publisher death unless values carry
   leases anyway. Only attractive if the publisher is a human shell.
3. **B2, kanata TCP notification channel as publisher** (parent-reported,
   v1.9.0): `push-msg` exists in code despite lacking a docs section —
   `PUSH_MESSAGE` in `parser/src/cfg/list_actions.rs`, `parse_pushmessage`
   around `parser/src/cfg/mod.rs:2624`, `ServerMessage::MessagePush` over
   the notification channel behind the `tcp_server` cargo feature;
   `tcp_protocol` has `MessagePush` but **no `SetVariable`**; the server
   sends an initial `LayerChange` on connect but generic pushes lack
   snapshots. **Concrete deployed blocker** (parent, read-only checks):
   `/usr/bin/kanata --help` exposes no `-p/--port`, which the
   version-matched CLI gates behind `#[cfg(feature="tcp_server")]` — the
   installed 1.9 binary appears built *without* the feature; and
   `/usr/lib/systemd/system/kanata.service` runs as `User=_kanata` with
   `PrivateNetwork=true`, `RestrictAddressFamilies` denial, and
   `IPAddressDeny=any`, with no port flag in `ExecStart`. Flipping config
   alone therefore cannot enable this path: it needs a rebuilt or
   alternative binary, an `ExecStart` change, and a deliberate service
   security/namespace decision. Treat B2 as blocked by default. Even if
   unblocked, the reconnect-snapshot gap (precision bit possibly wrong
   after reconnect until the next push) and the absent auth beyond
   localhost stand; and kanata has no config-triggered "modifier held"
   event out of the box — publishing Shift transitions requires authoring
   config that routes Shift through actions that also `push-msg`, and per
   the parent, **current layer must not be assumed equal to the precision
   bit**. Layer vocabulary is mode switching, not held-modifier state.
4. **B4, evdev observation** (no kanata changes at all — the dial daemon
   or a sibling user process watches):
   - **B4a, physical nodes directly**: blocked by grab exclusivity, as
     above. A partial variant is `EVIOCGKEY` ioctl sampling: the kernel's
     held-key bitmap is readable regardless of grab, so a poller can
     sample physical Shift state without an event stream. Costs: polling
     latency versus dial tick rate, no press/release edges (only levels),
     device-identity and hotplug bookkeeping, and it is inherently a
     snapshot feed. Acceptable as a coarse fallback or bootstrap, not as
     the primary held-bit channel.
   - **B4b, output-node watcher**: uinput outputs are ungrabbed by design
     (the compositor is a normal reader), and multiple readers of an
     evdev node each receive the full stream. Watching the **scoped
     kinata output** of the declared split yields exactly
     physical-keyboard events with clean provenance — no dial synthetic
     Shift is merged there. Watching **main's output** on the deployed
     single-instance topology is contaminated today (the dial's synthetic
     Shift is provenance-free once merged), but becomes provenance-clean
     **after A2 lands**, because A2 deletes the only synthetic Shift
     source. That is a real sequencing synergy: A2 first makes the
     simplest possible publisher — a name-matched udev watcher on main's
     output — safe regardless of which split is deployed. Watcher costs
     either way: output nodes churn (`eventN`) so discovery must match by
     name, default-named outputs are ambiguous across instances (all
     `kanata`; the renamed `kanata-kinata` candidate or path pinning
     disambiguates), and reconnect re-enumeration must re-attach. The
     daemon already owns exactly this machinery — a name-matched udev
     enumerator plus a reader thread (`events.rs`) — so a second watcher
     instance is a small, pattern-matching extension.

**Provenance subtlety that decides the publisher**: kanata's merged stream
is provenance-free (untagged events, coordinate-based state — kanata
assessment evidence). Any publisher watching the *merged* main output would
see the dial's own synthetic Shift as indistinguishable from physical
Shift: the daemon's emissions would echo back and **self-trigger the
precision bit**, a feedback loop. Three provenance-clean options remain:
the physical-keyboard-scoped kinata output of the declared split (B4b —
conventional and unprivileged, but the deployed topology currently differs
from that split), `EVIOCGKEY` sampling of the grabbed physical nodes
(B4a — works despite grabs, at latency/bookkeeping cost), or adopting A2
first, after which even main's merged output carries no synthetic Shift
and any watcher becomes clean. If Path B is chosen without A2, the
publisher must be the scoped instance or the sampling fallback, never the
merged instance. A complementary encoding exists only under B: physical
**Right** Shift as the precision bit (distinct coordinate even in a merged
kanata stream; same mask bit at Umbriel, so useless under A) while the
dial keeps synthesizing Left Shift.

**Integration point inside the daemon** (smallest coherent shape): the
controller loop already consumes a cross-thread "remote variable" at the
top of every dispatch — `new_mode: Arc<Mutex<Option<usize>>>`, checked
before each event ([`controller/mod.rs:78-84`](/home/rektide/src/surface-dial-layered/src/controller/mod.rs#L78-L84)).
A sideways channel reuses exactly this pattern: a `ControlState` cell
(Arc<Mutex<…>>) written by a small control-socket thread, read at dispatch
time. Because the main loop blocks on `device.next_event()`, a second
mpsc would need a select; the shared-cell-plus-lazy-read avoids all
restructuring. Held-bit expiry needs no timer thread either: evaluate
leases lazily at dispatch time (if `now > lease_expiry`, treat as
released). There is also an existing fail-safe precedent to mirror:
`Paddle::on_end` forces `key_release` of anything the mode had pressed
([`paddle.rs:68-78, 156-164`](/home/rektide/src/surface-dial-layered/src/controller/controls/paddle.rs#L68-L78));
mode exit and dial `Disconnect` should likewise reset latched precision
state.

### Proposed protocol sketch (v1, deliberately tiny)

Text datagrams, greppable, versioned; one variable per datagram:

```text
v1 set <mode>.<var> = <value>          # persistent policy override (step sizes)
v1 hold precision <acquire|release> gen=<n> lease_ms=<ms>   # held bit, default lease 2000
v1 reset                              # clear all held bits and non-default overrides
```

Semantics worth deciding up front:

- **Held bits are press/release with leases**, not toggles. Silence beyond
  the lease decays to released; publisher disconnect resets; daemon
  restart starts clean (only `last_mode` is persisted — precision must not
  become persisted state, or a crash latches "even finer" across sessions).
- **Unknown variables are rejected and logged**, not ignored silently.
- Overrides are per-control-mode policy (`volume.step`, `volume.step_fine`,
  `volume.detents`), preserving the brief's terminology separation between
  baseline synthetic Shift, physical keyboard Shift, selected control
  mode, and precision layer.
- Failure containment: today any `on_dial` error propagates through
  `controller.run()` → daemon exit
  ([`main.rs:41-56`](/home/rektide/src/surface-dial-layered/src/main.rs#L41-L56)),
  and the unit has **no `Restart=`**. Daemon-owned actuation must make
  per-event failures log-and-continue, and the unit needs a restart policy
  — a deployment-G note, but a hard prerequisite for B.

## Daemon-side actions vs emitting distinct keys

| Concern | Emit keys (A2) | Daemon-owned actuation (B0+B1) |
|---|---|---|
| New daemon code | ~5 lines (capabilities + chord swap) | socket thread, policy table, exec path, error policy |
| Step expressiveness | any `wpctl` arg via bindings | any value, plus **velocity scaling from `on_dial`'s i32 delta** — a modality only the daemon can see |
| Session/permissions | none (compositor execs act) | user-service identity; PipeWire/playerctl available; needs error containment + `Restart=` |
| Modality ceiling | modifier-mask combos, one key each | arbitrary held bits, toggles, per-mode overrides |
| Fail-safe | structural (stateless) | protocol discipline (leases, reset-on-disconnect, no persistence) |
| Blast radius | consumes reserved keys + new bindings | nothing global; dial behavior fully private |
| Compositor coupling | needs Umbriel bindings (parent domain) | compositor-independent |

The brief's modality ambitions — "held precision bit vs toggle/layers vs
control modes" — map cleanly: control modes already exist (persistent,
menu-selected, hardware-only switching); the precision modifier should be a
held bit, not a layer, to inherit fail-safe decay; toggles and per-mode
step overrides are exactly the `set`/`hold` split in the sketch. Haptic
detents ride along as ordinary per-mode config either way.

## Recommendation and smallest next slice

**A2 is the smallest coherent slice for the stated goal**: enable F23/F24
on the uinput keyboard, stop synthesizing Shift in the two volume modes,
emit the reserved direction keys, and let parent-side bindings carry
fine/even-finer with physically-held Shift. It needs no protocol, no
state, no session plumbing, and it deletes an existing collision hazard.
It is also the prerequisite-free path in a stricter sense now: the kanata
TCP publisher (B2) is blocked by the installed binary's missing
`tcp_server` feature *and* by the unit's network-denial hardening, and
direct physical-node observation as an event stream is blocked by grab
exclusivity — the only unblocked B publishers today are the declared
split's scoped output watcher (that topology is not currently deployed)
and `EVIOCGKEY` sampling (latency and bookkeeping costs). The B1 design
above remains the growth path if per-mode step policy, velocity-scaled
steps, or a toggle modality is later wanted; note the sequencing synergy
that after A2 a plain name-matched watcher on main's merged output is
provenance-clean, making B1+B4b reachable later without the split,
without kanata rebuilds, and without service security changes.

Concrete smallest slice, in dependency order:

1. Decide the encoding keys (F23/F24 vs another reserved pair) with the
   parent's keymap routing conclusion.
2. Daemon patch: two capability lines, two chord call sites (Volume,
   MediaWithVolume), matching detent `steps` if the smaller baseline
   wants finer tactile feedback.
3. Parent: media producer gains dial-scoped fine/even-finer bindings and
   the step values (0.02 / 0.005-class numbers are a user decision).
4. Verification belongs to deployment/input agents: dial-alone and
   Shift-held ticks against explicit expected deltas, plus the
   hold-Shift-rotate-type regression that the old synthetic Shift made
   risky.

## Unresolved questions

- Which source tree carries daemon patches going forward — the rektide
  fork (already 4 commits ahead), or a compfuzor-managed overlay on the
  declared `/usr/local/src/surface-dial-git`? The three-way divergence is
  currently unowned.
- Kanata TCP publisher: the installed binary appears to lack `tcp_server`
  and the unit denies networking (parent's read-only evidence). If B2 is
  ever wanted, is a rebuilt binary plus a deliberate service
  security/namespace decision on the table, or is B2 closed in favor of
  B4b watchers / B4a sampling?
- If Path B is pursued without A2: which provenance-clean publisher — the
  scoped kinata output (requires actually deploying the declared split)
  or `EVIOCGKEY` sampling (requires accepting poll latency and hotplug
  bookkeeping)? With A2 first, main's output watcher is clean — is that
  the agreed sequencing?
- Watcher identity details if B4b is chosen: name-matched discovery must
  disambiguate default-named `kanata` outputs across instances (renamed
  `kanata-kinata` candidate or path pinning); who owns the watcher
  process — the dial daemon itself, or a sibling that feeds B1?
- Actual session keymap for the chosen reserved keys (parent's fixture
  says default works; session-level confirmation pending).
- Step values and ratio: "significantly smaller baseline" and "reduced
  ratio" are still numbers nobody has picked; haptics detent count should
  move with them.
- Under A2, does anything legitimately want the dial's old synthetic-Shift
  fine chord preserved for other consumers (the
  [`media-keys.etc.pb`](/media-keys.etc.pb) comment says its vocabulary
  mirrors the dial's chords — that comment goes stale under A2 and the
  plain-keyboard Shift bindings keep their existing meaning for real
  keyboards)?
- Kinefolk background/registration (brief item 3) is not covered here; it
  was outside this daemon-architecture tasking.

## Cross-references

- [Wave brief](/design/surface-dial-layers/brief0.gpt61s.md): goals,
  boundaries, and the terminology separation this doc preserves.
- [Input assessment](/design/surface-dial-input/assessment0.gpt61s.md):
  the verified Umbriel cross-keyboard modifier aggregation Path A depends
  on, and why extra Shift cannot create a second level on its own.
- [Kanata assessment](/design/surface-dial-input/kanata-assessment0.gpt61s.md):
  merge mechanics, provenance loss, and the same-coordinate release hazard
  A2 removes; also the fixed capability list of the dial's virtual
  keyboard.
- [Prior diagnosis](/design/surface-dial/diagnosis0.glm53.md): the
  end-to-end synthetic chord verification and the deployment source
  location.
- [Action audiences inquiry](/design/action-audiences/intent0.gpt61sol.md):
  user-first action direction that a daemon-owned actuation path would
  follow.
- [`surface-dial.src.pb`](/surface-dial.src.pb) and
  [`media-keys.etc.pb`](/media-keys.etc.pb): declared deployment and
  binding policy these designs would amend.
- Daemon-local discovery docs:
  [`config-control-state-reference.md`](/home/rektide/src/surface-dial-layered/doc/discovery/config-control-state-reference.md)
  (pre-existing full state inventory; this doc's architecture section
  agrees with it and adds the interface inventory and channel designs).
