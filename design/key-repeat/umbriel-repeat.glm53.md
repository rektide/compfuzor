---
type: DesignInquiry
title: Umbriel key repeat — pipeline, tweakables, and the per-key accelerating-repeat patch surface
description: How repeat actually works end-to-end on this host (libinput → wlroots 0.20 → umbriel → Wayland/X11 clients), what config-only knobs exist today (global + per-device), and a ranked map of patch options in umbriel @ 71291ac for per-key accelerating pgup/pgdn repeat, with injection points, guards, and client-behavior caveats.
resource: /design/key-repeat/umbriel-repeat.glm53.md
status: draft
generated: { by: model:glm-5.3, at: 2026-10-07 }
stale_after: 2027-01-07
sources:
  - resource: https://github.com/noctalia-dev/umbriel/tree/71291ac
    title: Umbriel source @ 71291ac (verified: running /usr/local/bin/umbriel md5-matches /usr/local/src/umbriel-git/build-release/umbriel; archive tree ~/archive/noctalia-dev/umbriel and deployed worktree /usr/local/src/umbriel-git/repo both at 71291ac, VERSION 0.1.0)
  - resource: https://gitlab.freedesktop.org/wlroots/wlroots/-/tree/0.20.2
    title: wlroots 0.20.2 (installed libwlroots-0.20 0.20.2-1 via apt; source extracted to ~/tmp-opencode/wlroots-src/wlroots-0.20.2 from the Debian orig tarball)
  - resource: https://gitlab.freedesktop.org/libinput/libinput/-/tree/1.31.3
    title: libinput 1.31.3 (installed libinput-dev 1.31.3-1; source from Debian orig tarball, same local dir)
  - resource: /usr/share/wayland/wayland.xml
    title: Installed Wayland core protocol (wl_keyboard.repeat_info event description)
  - resource: /usr/local/share/umbriel/config.toml
    title: Live umbriel default config ([input.keyboard] repeat_rate = 25, repeat_delay = 600; [[input.device]] examples)
  - resource: /design/kanata-devices/init0.glm53.md
    title: Prior deep source map of deployed kanata revision (2f84d17)
  - resource: /design/key-repeat/kanata-repeat.glm53.md
    title: Companion kanata-side investigation (same wave)
  - resource: /design/key-repeat/umbriel-live-reload.glm53fx.md
    title: Companion live-reload investigation (may not exist yet at read time)
---

# Stage

The user wants a faster key repeat rate, and ultimately **per-key accelerating
repeat**: hold `pgup`/`pgdn` → repeats that ramp up the longer the key is held
(e.g. ~8/s growing to ~40/s), reverting on keyup. They believe the compositor is
the right layer. This document investigates the **umbriel** side: what the
repeat pipeline actually is, what factors filter into it, what is tweakable
today with zero code, and exactly where patches for per-key ramps would land.
The kanata side is covered by the companion
[kanata-repeat](/design/key-repeat/kanata-repeat.glm53.md) investigation; the
config-reload machinery by
[umbriel-live-reload](/design/key-repeat/umbriel-live-reload.glm53fx.md).

Reality on this host (from [kanata-devices](/design/kanata-devices/init0.glm53.md)
and live checks): every real keyboard is grabbed by kanata (main instance) and
re-emitted on a uinput keyboard named `kanata`; a second kanata instance
(`kanata-blueturn.srv.pb`, running now as pid 235263 with
`/etc/kanata/blueturn.kbd`) does the same for the iRig BlueTurn footpedal, whose
LEFT/RIGHT are momentary `pgup`/`pgdn`. Verified live in `/proc/bus/input/devices`:
exactly one input node named `kanata` exists right now (input474, event21; both
kanata instances name their uinput output `kanata`, per the companion doc), plus
direct evdev nodes for the Keychron/Kinesis keyboards, `ydotoold virtual device`,
and `vicinae-snippet-virtual-keyboard`. Umbriel 0.1.0 (commit `71291ac`) is the
running compositor, wlroots 0.20.2 and libinput 1.31.3 are underneath it.

# Verdict up front

1. **Repeat experienced by Wayland clients is 100% client-side.** The
   compositor's entire role is to send *one* `wl_keyboard.key` press event and a
   `wl_keyboard.repeat_info` (rate, delay) value; wlroots 0.20 has **no
   server-side repeat timer**, and libinput drops kernel/hardware repeats before
   they ever reach wlroots (`evdev-fallback.c` "ignore kernel key repeat").
   `kbdrate`, keyboard firmware repeat, and kanata hold behavior are all
   irrelevant to what kitty experiences. Changing repeat = changing what
   `repeat_info` says (or synthesizing key events yourself).
2. **Umbriel already applies config-driven repeat_info live.** Config
   `repeat_rate`/`repeat_delay` flow to `wlr_keyboard_set_repeat_info`, which
   emits a signal the seat forwards as a fresh `wl_keyboard.repeat_info` event
   to **every** connected client — and the Wayland protocol explicitly blesses
   mid-session updates ("This event can be sent later on as well with a new
   value if necessary"). A config reload re-applies it. So a *static* per-key or
   per-device rate change is a solved problem; only *acceleration* needs code.
3. **Per-device keyboard config is real and applies to kanata.** It is
   `[[input.device]]` with `name = "kanata"` (exact string match against the
   libinput device name — which for uinput devices is the uinput name), **not**
   the `[input.keyboard."Name"]` dotted form (that syntax doesn't exist; the
   default config file's commented example is `[[input.device]]`). Since both
   kanata instances emit on uinput nodes named `kanata`, one device section
   covers essentially all user typing. Virtual (Wayland-protocol) keyboards are
   excluded from config, but kanata's uinput devices are *not* virtual in that
   sense — they're ordinary libinput keyboards.
4. **The pragmatic ranked path**: (0) config-only per-device/global bump today;
   (A′) tiny patch — per-key two-rate (fast while a configured key is held);
   (A″) small patch — stepped acceleration by re-sending `repeat_info` on a
   ramp timer, *viable only if clients honor mid-hold updates* (cheap
   config-only experiment to verify, see below); (B) medium patch —
   compositor-synthesized tap events with `rate = 0` while held, the only
   option that accelerates *identically for every client* including X11 via
   xwayland-satellite. (C) "observe without consuming" keybinds do **not**
   exist today — every matched bind consumes both halves of the event.
5. **Don't**: don't chase hardware repeat (dead at libinput), don't expect
   wlroots to synthesize repeats for you, don't bind `pgup` to an action hoping
   it still reaches windows (binds consume), don't exceed the validated ranges
   (`repeat_rate` 0–1000, `repeat_delay` 0–10000 ms).

# Revision pinning (how these citations were verified)

| What | Value | Evidence |
|---|---|---|
| Running binary | `/usr/local/bin/umbriel`, VERSION 0.1.0 | `pgrep`; binary string `starting umbriel version={} commit={}` |
| Source the binary was built from | commit `71291ac` ("Tests for scrolling reveal and snap padding") | md5 `2669c700…` of `/usr/local/bin/umbriel` **equals** `/usr/local/src/umbriel-git/build-release/umbriel`; worktree `/usr/local/src/umbriel-git/repo` and archive `~/archive/noctalia-dev/umbriel` both at `71291ac`, clean |
| wlroots | 0.20.2 (apt `libwlroots-0.20-dev 0.20.2-1`) | `dpkg -l`; umbriel `meson.build` pins `wlroots-0.20 >=0.20.1 <0.21.0`; source verified against the Debian 0.20.2 orig tarball |
| libinput | 1.31.3 | `dpkg -l libinput-dev`; source from Debian orig tarball |

All `src/…` file:line citations below are exact at `71291ac`. Canonical URL
shape: `https://github.com/noctalia-dev/umbriel/blob/71291ac/src/…`; local
readable copies at both trees above. wlroots citations:
`https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/…` (local copy at
`~/tmp-opencode/wlroots-src/wlroots-0.20.2/`).

# The repeat pipeline, end to end

```mermaid
flowchart TD
    subgraph kernel["kernel"]
        HW["physical key held<br/>EV_KEY value=2 autorepeats"]
    end
    subgraph libinput["libinput 1.31.3"]
        LI["evdev-fallback.c:591<br/>value==2 (repeat) DROPPED<br/>only real press/release pass"]
    end
    subgraph wlroots["wlroots 0.20.2"]
        BE["libinput backend<br/>handle_keyboard_key<br/>(every event: press or release)"]
        WK["wlr_keyboard<br/>· keycodes set<br/>· repeat_info rate/delay<br/>· events.repeat_info signal"]
        SEAT["wlr_seat<br/>· ONE active keyboard<br/>· set_keyboard re-sends repeat_info<br/>· on repeat_info change: push to ALL clients"]
    end
    subgraph umbriel["umbriel @ 71291ac"]
        KB["Keyboard::handleKey<br/>keyboard.cpp:241"]
        BIND["bind engine<br/>(consumed or not)"]
        APPLY["Keyboard::applyConfig<br/>keyboard.cpp:79<br/>wlr_keyboard_set_repeat_info"]
        TIMER["m_repeatTimer<br/>keyboard.cpp:402-449<br/>repeats BIND ACTIONS only"]
    end
    subgraph clients["clients"]
        WL["Wayland native (kitty…)<br/>own repeat timer from repeat_info"]
        XW["xwayland-satellite<br/>is itself the wl_keyboard client;<br/>generates X autorepeat for X11 apps"]
    end
    HW -->|evdev| LI --> BE --> WK
    WK -->|events.key| KB --> BIND
    BIND -- "unhandled" -->|"wlr_seat_keyboard_notify_key :376"| SEAT
    BIND -- "matched (consumed)" --> TIMER
    TIMER -.->|executeKeybindAction<br/>never reaches clients| BIND
    APPLY --> WK
    SEAT -->|"wl_keyboard.key (1 press)"| WL
    SEAT -->|"wl_keyboard.repeat_info (rate,delay)"| WL
    SEAT --> WL2["repeat events synthesized<br/>entirely client-side"]
    WL2 -.-> WL
    SEAT --> XW
```

Step by step, with citations:

1. **Kernel autorepeat never arrives.** libinput's fallback dispatcher drops
   every EV_KEY event with `value == 2` (repeat):
   [`src/evdev-fallback.c:589-592`](https://gitlab.freedesktop.org/libinput/libinput/-/blob/1.31.3/src/evdev-fallback.c#L589)
   (`/* ignore kernel key repeat */`). So `kbdrate` and any EV_REP behavior of
   kanata's uinput output are dead letters downstream.
2. **wlroots' libinput backend is a dumb pipe for real transitions.** Every
   libinput key event becomes a `wlr_keyboard_key_event` (PRESSED or RELEASED,
   `update_state = true`) and is emitted from `wlr_keyboard.events.key`:
   [`backend/libinput/keyboard.c` `handle_keyboard_key`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/backend/libinput/keyboard.c).
3. **wlroots has no repeat timer.** `wlr_keyboard_notify_key` updates the
   pressed-keycode set, emits the key signal, and updates xkb state — nothing
   else: [`types/wlr_keyboard.c:110-131`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/wlr_keyboard.c#L110).
   `repeat_info` is pure data (default 25/600 at init,
   [`types/wlr_keyboard.c:139-141`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/wlr_keyboard.c#L139)).
   `wlr_keyboard_set_repeat_info` stores the values and — *only if either
   changed* — emits `events.repeat_info`:
   [`types/wlr_keyboard.c:288-296`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/wlr_keyboard.c#L288).
4. **The seat pushes repeat_info to every client, live.** The seat listens to
   the active keyboard's `repeat_info` signal and re-sends
   `wl_keyboard.repeat_info` to **all** seat clients whose wl_keyboard resource
   is version ≥ 4:
   [`types/seat/wlr_seat_keyboard.c:100-108`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/seat/wlr_seat_keyboard.c#L100)
   and
   [`:379-397`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/seat/wlr_seat_keyboard.c#L379).
   Calling `wlr_seat_set_keyboard` with a *different* keyboard also re-sends
   repeat_info from the new one
   ([`:116-163`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/seat/wlr_seat_keyboard.c#L116);
   same-keyboard calls early-return at `:121`). The Wayland protocol explicitly
   allows re-sending: "This event can be sent later on as well with a new value
   if necessary, so clients should continue listening for the event past the
   creation of wl_keyboard" —
   [`/usr/share/wayland/wayland.xml:2732-2751`](https://gitlab.freedesktop.org/wayland/wayland/-/blob/main/protocol/wayland.xml#L2732).
   A rate of 0 disables client repeat, regardless of delay.
5. **Umbriel's keyboard handling.** Each input device becomes one `Keyboard`
   (`Server::addKeyboard`,
   [`src/server/server_events.cpp:1366-1388`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/server/server_events.cpp#L1366);
   Wayland-protocol virtual keyboards wait for a keymap first, `:876-894`).
   `Keyboard::applyConfig`
   ([`src/input/keyboard.cpp:47-85`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.cpp#L47))
   resolves per-device overrides with global fallback
   (`repeatRate`/`repeatDelay` at `:57-59`), skips virtual keyboards entirely
   (`:49-51`), and lands on `wlr_keyboard_set_repeat_info(m_keyboard,
   repeatRate, repeatDelay)` at
   [`:79`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.cpp#L79).
6. **Per key event** (`Keyboard::handleKey`,
   [`src/input/keyboard.cpp:241-385`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.cpp#L241)):
   press → idle activity, VT-switch check, quit-confirm check, then bind
   matching (`:308-326`). A matched bind sets `handled = true` and records the
   keycode in `m_consumedKeycodes` (`:314`, `:347`) so the release is swallowed
   too (`:359`). **Only unhandled events are forwarded** —
   `wlr_seat_set_keyboard` + `wlr_seat_keyboard_notify_key` at
   [`:375-376`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.cpp#L375),
   or into an input-method grab when one is active (`:362-366`). An open
   overview with no focused layer surface swallows keys instead (`:371-377`).
7. **What clients receive during a held key**: exactly one `wl_keyboard.key`
   press (plus the earlier `repeat_info`), then silence until keyup. Kitty &
   co. run their own timer: after `delay` ms, repeat at `rate` Hz. X11 apps
   through **xwayland-satellite**: satellite is itself the Wayland client, so
   *it* implements repeat from `repeat_info` and feeds autorepeat into its X
   server; umbriel never talks to X11 clients directly. Umbriel's own docs
   treat satellite behaviors as an invariant-protecting hazard class
   ([`docs/design/xwayland-input-stability.md`](https://github.com/noctalia-dev/umbriel/blob/71291ac/docs/design/xwayland-input-stability.md)).
8. **Umbriel's own repeat timer is for bind actions, not keys.**
   `armRepeat`/`onRepeatTimer`
   ([`src/input/keyboard.cpp:402-449`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.cpp#L402))
   re-execute a *matched keybind's action* while its key is held, at
   `1000 / repeat_info.rate`, after `repeat_info.delay` — i.e. the existing
   precedent for compositor-side timed re-fire, and a natural host for ramp
   logic. It never synthesizes key events for clients.

## Multi-keyboard subtlety

The seat tracks **one** active keyboard
(`wlr_seat_keyboard_state.keyboard`). Every unhandled key/modifier event calls
`wlr_seat_set_keyboard`, and a *switch* between keyboards re-sends repeat_info
from the newly active one to all clients. With different per-device rates, the
clients' effective repeat is "whichever keyboard last produced an event." On
this host nearly everything flows through the single `kanata` uinput name, so
in practice a per-device rate on `kanata` behaves like a global rate for user
typing — the flip-flop only matters if you type directly on a non-grabbed
keyboard mid-session.

# Per-device config: real, exact-name, and it covers kanata

| Question | Answer | Citation |
|---|---|---|
| Is per-device keyboard config real? | Yes: `[[input.device]]` array of tables; `name` required and must be unique; `repeat_rate` 0–1000, `repeat_delay` 0–10000 validated | [`src/config/config.cpp:1544-1599`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/config/config.cpp#L1544) (`:1561-1562` ranges) |
| How are names matched? | Exact `==` on `wlr_input_device.name`, which for libinput devices is the libinput/udev name — for uinput devices, the uinput name | `findDevice` [`src/config/config.cpp:2533-2536`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/config/config.cpp#L2533); device name captured in `Keyboard` ctor [`src/input/keyboard.cpp:28`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.cpp#L28) |
| Does it apply to kanata's uinput keyboards? | Yes. `m_virtual` is only true for Wayland-protocol virtual keyboards (`wlr_input_device_get_virtual_keyboard`); uinput devices arrive as ordinary libinput keyboards. Both kanata instances output on nodes named `kanata`, so one section covers both | [`src/input/keyboard.cpp:27-31,49-51`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.cpp#L27); live `/proc/bus/input/devices` `N: Name="kanata"` |
| Different rate for kanata vs other keyboards? | Yes, but see the multi-keyboard note — last-active-keyboard wins for what clients currently repeat at | wlroots `wlr_seat_keyboard.c:116-163` |
| Docs | `docs/user/input.md` "Per-device overrides" (exact name, `repeat_rate`/`repeat_delay` listed as overridable); examples at `examples/config.toml:273-279` | [`docs/user/input.md:261-293`](https://github.com/noctalia-dev/umbriel/blob/71291ac/docs/user/input.md#L261) |

Caveat: exact-name matching is literal. If the kanata uinput name ever changes,
the section silently stops applying (same fragility the blueturn include
documents for its own device matching).

# Tweakables available today, zero code

| Knob | Where | Values / notes |
|---|---|---|
| `[input.keyboard] repeat_rate` | [`config.cpp:1618`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/config/config.cpp#L1618), default 25 ([`config.h:772`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/config/config.h#L772)) | 0–1000 Hz; **0 disables client repeat entirely** (protocol-defined) |
| `[input.keyboard] repeat_delay` | [`config.cpp:1619`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/config/config.cpp#L1619), default 600 | 0–10000 ms |
| `[[input.device]] name="kanata"` per-device `repeat_rate`/`repeat_delay` | [`config.cpp:1561-1562`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/config/config.cpp#L1561) | Same ranges; overrides global for that device only |
| Bind `repeat = false` (table-form binds) | `Keybind::repeat` [`keybind_parse.h:223`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/config/keybind_parse.h#L223); docs [`docs/user/keybinds.md:88-98`](https://github.com/noctalia-dev/umbriel/blob/71291ac/docs/user/keybinds.md#L88) | Stops *bind action* repetition only; no effect on client key repeat |
| Bind `cooldown_ms`, `allow_when_locked`, `allow_when_inhibited` | [`keybind_parse.h:224-226`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/config/keybind_parse.h#L224) | Bind-action gating; orthogonal to client repeat |
| Live reload of any of the above | reload → `effects.input` → `keyboard->applyConfig()` for every keyboard → `wlr_keyboard_set_repeat_info` → clients get fresh repeat_info mid-session | [`server_events.cpp:512-516`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/server/server_events.cpp#L512); mechanism detailed in the companion [umbriel-live-reload](/design/key-repeat/umbriel-live-reload.glm53fx.md) doc |
| Keyboard hardware repeat (`kbdrate`), kanata output cadence | — | **No effect**: kernel repeats dropped at libinput `evdev-fallback.c:591`; see also [kanata-repeat](/design/key-repeat/kanata-repeat.glm53.md) §pipeline |

**Zero-code experiment worth running first** (it de-risks patch option A
below): edit the user config's `repeat_rate` while holding a key in kitty and
trigger a reload. If kitty's in-flight repeat speeds up mid-hold, clients
re-apply repeat_info live and options A′/A″ are viable for kitty; if not, only
option B gives true mid-hold acceleration. This experiment needs no code
because reload already re-sends repeat_info. (Check kitty, a GTK app, an SDL
app, and an X11 app via xwayland-satellite — they may differ.)

# Per-key accelerating repeat — patch surface

All options share one entry point for key detection:
`Keyboard::handleKey`'s press branch
([`keyboard.cpp:263-353`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.cpp#L263))
where `syms[]` are already resolved (`:250-255`) and before forwarding at
`:362-379`; keyup at `:354-360`. Config surface would naturally live beside
`[[input.device]]` parsing (`config.cpp:1544+`) or as a new
`[input.keyboard.ramp]` keysym table parsed near
`config.cpp:1614-1628`. The existing per-Keyboard timer machinery
(`m_repeatTimer`, `wl_event_loop_add_timer`, `armRepeat`/`cancelRepeat`/
`onRepeatTimer` at
[`keyboard.cpp:402-449`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.cpp#L402),
members in
[`keyboard.h:81-86`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/input/keyboard.h#L81))
is the structural precedent to copy: per-device timer, armed on qualified press,
cancelled on keyup/modifier change/destroy, guards for session-lock and
shortcut-inhibition already modeled at `:437-443`.

## Option A′ — per-key two-rate via live repeat_info mutation (S, ~20–40 LOC)

On keydown of a configured keysym (e.g. `Page_Up` from device `kanata`):
`wlr_keyboard_set_repeat_info(m_keyboard, fastRate, fastDelay)`. On keyup:
restore the config-resolved rate/delay (recompute exactly like `applyConfig`
`:57-59` — a reload may have changed the base values mid-hold).

- **Does wlroots re-send repeat_info mid-session?** Yes, immediately, to all
  clients (v≥4): `wlr_keyboard.c:288-296` → `wlr_seat_keyboard.c:100-108`.
  Dedupe on equal values is harmless here (set→fast→restore always differs,
  and identical no-ops skip the broadcast).
- **Do clients honor it?** Protocol-blessed to be re-sent; whether a *mid-hold*
  update restarts an in-flight repeat timer is client-specific — hence the
  zero-code experiment above. kitty is the main consumer; unverified (see
  unresolved questions).
- **Where**: `handleKey` press/release branches; store the restore values next
  to the timer state in `keyboard.h`. Skip when the key was consumed by a bind
  (it never reaches clients, so no repeat exists to retune).
- **Guards**: modifier changes call `cancelRepeat()` today (`:227`); a
  mid-hold modifier press would want to leave the fast rate alone (the key is
  still held) — the rate belongs to the *held key*, not the timer. Restore on
  destroy (`handleDestroy` `:387-391`) and on VT switch
  (`forgetConsumedKeycodes` precedent `:349-353`) to avoid leaking the fast
  rate session-wide.
- **Limit**: one rate per keyboard, not a ramp. Two keys held simultaneously on
  the same keyboard (pgup from pedal + typing on main — but note both instances
  share the uinput *name*, not the *node*; each uinput node is a separate
  `Keyboard` object, so per-object state is fine) each bump their own object.

## Option A″ — stepped acceleration via repeat_info updates (S–M, ~60–100 LOC)

A′ plus a timer that bumps the rate while the key stays held: e.g. thresholds
at 300/700/1200 ms stepping 8 → 15 → 25 → 40 Hz. Each bump is one
`wlr_keyboard_set_repeat_info` call → one protocol event per client. Reuse the
`m_repeatTimer` pattern with a second timer (or generalize it).

- **Client caveat is decisive**: a client that only reads repeat_info at
  keypress will ignore mid-hold bumps; one that restarts its timer on each
  event will accelerate cleanly. If kitty restarts on the event (verify!), this
  is the cheapest true accelerator for Wayland-native apps. Per-step protocol
  chatter is negligible (a few events per hold).
- **Delay re-arming subtlety**: if the client restarts its delay window on each
  repeat_info event (rather than just re-reading rate), stepped updates would
  re-introduce the initial delay each step — i.e. pauses instead of
  acceleration. The experiment distinguishes restart-timer vs re-read-rate;
  only the latter makes A″ work. This is exactly the kind of thing the
  zero-code reload experiment reveals.
- **X11**: depends on whether xwayland-satellite re-reads repeat_info mid-hold
  (unverified; satellite source not inspected here).

## Option B — compositor-synthesized repeats, `rate = 0` while held (M, ~150–250 LOC)

Umbriel synthesizes additional key events for the held key on its own ramping
timer; client-side repeat is suppressed for that keyboard while synthesis is
active, so there is no double-firing.

- **Injection point**: call `wlr_seat_keyboard_notify_key(seat, now_msec,
  keycode, state)` per synthesized event — the same call umbriel already makes
  at `keyboard.cpp:376`. Prefer synthesizing **full taps** (release + press, or
  press + release after one interval) over bare presses: a bare press leaves
  the key logically down in the client, and focus changes mid-hold hand held
  keys to the new client via `wl_keyboard.enter`'s keys array — the exact
  stranded-key class umbriel already defends against for consumed binds
  ([`server_events.cpp:2484-2505`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/server/server_events.cpp#L2484),
  "XWayland turns that into an endless key repeat"). Self-contained taps are
  immune to stuck keys by construction. Caveat to verify: tap = key release +
  press produces two X events per repeat in XWayland; some X apps (games)
  treat that differently from autorepeat — acceptable for pgup/pgdn targets
  (terminals, browsers) but worth noting.
- **Suppressing client repeat**: on synthesis start, `wlr_keyboard_set_repeat_info(kb, 0, 0)`
  (protocol: rate 0 disables repeat); on keyup/synthesis end, restore config
  values. All clients honor this because they must honor it to show *no*
  repeat.
- **Ramp**: fully compositor-owned — start 8/s, ramp to 40/s on any curve;
  re-arm `wl_event_source_timer_update` each fire (the `onRepeatTimer`
  `:447` pattern), interpolating the interval rather than stepping.
- **Guards required** (each has an in-tree precedent):
  - keyup of the real key ends synthesis (track keycode; `m_repeatKeycode`
    pattern `:412`);
  - key consumed by a bind → never synthesize (it isn't visible to clients);
  - input-method grab active → route synthesized events through the grab
    (`activeInputMethodGrab()` `:362-366`) or suspend synthesis;
  - overview holding the seat / no focused surface → suspend (`:371-377`);
  - session lock / shortcuts inhibit → cancel (`onRepeatTimer` precedent
    `:437-443`);
  - focus change mid-hold → keep synthesizing into whatever is focused
    (taps are focus-agnostic) or cancel; either is safe with full taps;
  - device destroyed mid-hold → timer removed (`handleDestroy` `:387-391`);
  - multiple keyboards → per-`Keyboard` state; two instances emitting pgup
    simultaneously each ramp independently (nodes are distinct `Keyboard`s
    even though both are named `kanata`).
- **Why it's the most robust**: semantics are identical for every client —
  kitty, GTK, Qt, SDL, and X11-via-satellite all just see key events. No
  dependence on per-client repeat_info re-read behavior. Cost: umbriel becomes
  a repeat source, which upstream's SCOPE may read as "reimplementing what
  wlroots provides" (see lineage below) — likely fine as a local patch, harder
  as an upstream PR.

## Option C — existing machinery that could observe pgup without consuming it

**None today.** Every matched bind consumes both halves of the event
(`m_consumedKeycodes`, `keyboard.cpp:314,347,359`; documented at
`docs/user/keybinds.md:80-86`), and there is no pass-through/observe action in
the 60+ action vocabulary (`KeybindAction` enum,
[`keybind_parse.h:29-153`](https://github.com/noctalia-dev/umbriel/blob/71291ac/src/config/keybind_parse.h#L29)).
Submaps, cooldowns, and `spawn` are all consuming. Two creative extensions the
source suggests if C-like behavior is wanted:

- a bind action `key-tap:<keysym>` (or IPC `umbriel msg tap-key Page_Up`) that
  synthesizes a tap into the focused surface — composes with the existing
  keybind repeat timer to give a **config-only accelerating bind**
  (`Page_Up` bound to a tap action, `repeat = true`, riding
  `repeat_rate`/`repeat_delay`)… except that still can't *accelerate*, only
  repeat at fixed rate, and the bind consumes the real key (fine — the action
  replaces it). This is M-sized (new action + synthesis helper shared with
  option B) and doubles as scripting surface for the kanata side (compare
  ActOnFakeKey in [kanata-repeat](/design/key-repeat/kanata-repeat.glm53.md)).
- a per-key ramp config section parsed alongside `[[input.device]]`
  (`[input.keyboard.ramp]` keysym table: `start_rate`, `end_rate`,
  `ramp_ms`) feeding either A″ or B — the natural upstream-facing surface.

# Upstream, lineage, and maintenance

- Umbriel is **not a fork of sway/niri/hyprland**: an original C++23 compositor
  by noctalia-dev, a "thin compositor layer over wlroots 0.20 and `umbrielfx`,
  its own hard fork of SceneFX" (`SCOPE.md` preamble; `README.md`). Xwayland
  via xwayland-satellite as a separate process.
- History: 1027 commits, first 2026-08-02, latest 2026-10-06 — young and
  fast-moving; README warns "configuration keys, keybinds, and behavior may change
  between releases." Local patches are against `71291ac`, deployed and archived
  trees identical, so maintenance = rebasing a small series against a
  fast-moving upstream.
- `SCOPE.md` gates: "input handling" refinement is **in scope**; "new
  configuration keys that expose behavior Umbriel already implements" in
  scope; "**reimplementing what wlroots provides**" **out of scope**. A
  per-device/per-key *rate* config is squarely in scope; compositor-synthesized
  repeat (option B) arguably re-implements a client-side concern server-side —
  a local patch or a carefully-argued issue conversation, not a quick PR. A
  `key-tap` action (option C) is closer to upstream taste (it extends the
  existing action vocabulary).
- Prior thinking on input/repeat in-tree: `docs/user/input.md` and
  `docs/user/keybinds.md` (user docs), `docs/design/xwayland-input-stability.md`
  (X11 input hazards; the closest thing to repeat-related design notes — the
  stranded-held-key class). Nothing on per-key or accelerating repeat exists
  upstream; `design/` at repo root holds only `window-navigation`.

# Risks

| Risk | Options affected | Notes |
|---|---|---|
| Clients ignore mid-hold repeat_info updates (re-read only at keypress) | A′, A″ | De-risked by the zero-code reload experiment before writing code |
| Clients re-read rate but restart the *delay* window per event | A″ | Turns acceleration into stutter; same experiment reveals it |
| xwayland-satellite repeat_info handling differs from kitty | A′, A″ | Verify X11 path separately; B is immune |
| set_repeat_info dedupe hides a restore no-op | A′/A″ | Only if fast rate == base rate; recompute base from config each time (reload can change it) |
| Stuck logically-down keys in clients on focus change mid-synthesis | B (press-only variant) | Use full taps; the codebase's own XWayland comment (`server_events.cpp:2486`) names this failure class |
| Double repeat (client timer + synthesis) | B | Suppress with rate=0 while synthesizing; restore on keyup; verify restore on destroy/lock/VT paths |
| Config reload mid-hold resets rate under an active ramp | A′, A″, B | Re-derive per-hold state from config at arm time; `applyConfig` (`:47`) currently calls `cancelRepeat()` first — a ramp must survive or re-arm coherently; coordinate with the reload companion doc |
| Upstream churn rebases | all | 1027 commits in ~9 weeks; keep the series small and config-driven |
| Per-device exact-name match silently misses a renamed uinput node | config-only, A′/A″ device scoping | Same fragility kanata's includes already document |

# Unresolved questions for the parent

1. **Do target clients re-apply repeat_info mid-hold, and do they re-read
   rate-only or restart the delay?** (kitty first, then GTK/Qt, then an X11 app
   under xwayland-satellite.) The config-edit + reload experiment answers this
   with zero code and decides A″ vs B. This is *the* gating question.
2. **Which target surface matters most — kitty only, or X11 too?** If X11
   (BlueTurn paging through PDFs in an X reader?), B's uniform semantics weigh
   heavier; verify satellite's behavior during the same experiment.
3. **Scope of the ramp**: per-keysym globally, or per-device+keysym (only
   `kanata`-emitted pgup/pgdn)? Device-scoping is nearly free (state is already
   per-`Keyboard`) and avoids surprising direct-attached keyboards.
4. **Does the user want the bind-action repeat (`repeat = true` binds) ramped
   too?** Orthogonal machinery (`armRepeat`), same config surface could cover
   it later.
5. **Upstream appetite**: worth opening a noctalia-dev issue for per-key ramp
   config before building locally? SCOPE's "wlroots-provided" line suggests
   framing matters; a `key-tap` action or per-key rate override reads more
   upstream-compatible than full synthesis.
6. For the reload companion: confirm what `effects.input` covers on a
   repeat-only config edit (does a rate-only change reach `keyboard->applyConfig`
   without a full re-init?) — affects both the experiment and patch restore
   paths.

# Cross-references

- [`/design/key-repeat/kanata-repeat.glm53.md`](/design/key-repeat/kanata-repeat.glm53.md) — companion kanata-side investigation; establishes both kanata instances emit on uinput named `kanata`, hardware repeat dies before the compositor, and proposes a kanata-lane ActOnFakeKey ramp. The two lanes are alternatives: compositor-side (this doc) vs kanata-side.
- [`/design/key-repeat/umbriel-live-reload.glm53fx.md`](/design/key-repeat/umbriel-live-reload.glm53fx.md) — companion reload investigation; the reload path (`effects.input` → `applyConfig`) is what makes the zero-code repeat experiment possible and what a ramp patch must survive.
- [`/design/kanata-devices/init0.glm53.md`](/design/kanata-devices/init0.glm53.md) — deployed kanata revision's source map; grounds the device topology and uinput naming facts used here.
- [`docs/design/xwayland-input-stability.md` @ 71291ac](https://github.com/noctalia-dev/umbriel/blob/71291ac/docs/design/xwayland-input-stability.md) — in-tree design notes on X11 input hazards; the stranded-held-key class any synthesis patch must respect.
- [`SCOPE.md` @ 71291ac](https://github.com/noctalia-dev/umbriel/blob/71291ac/SCOPE.md) — the in/out-of-scope rubric that shapes which patch options are upstreamable.
