---
type: DesignInquiry
title: Umbriel live config reload and runtime repeat mutation
description: How a running umbriel picks up config changes (inotify hot reload, config-reload keybind, IPC msg), whether reload re-applies [input.keyboard] repeat settings to live keyboards, whether wlroots 0.20 propagates repeat_info to focused clients, and ranked designs for the hold-pgup/accelerate/restore loop.
resource: /design/key-repeat/umbriel-live-reload.glm53fx.md
status: draft
generated: { by: model:glm-5.3-flash-max, at: 2026-10-07 }
stale_after: 2027-01-07
sources:
  - id: umbriel-src
    resource: https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/
    title: umbriel @ 71291ac "Tests for scrolling reveal and snap padding" (VERSION 0.1.0, wlroots >=0.20.1,<0.21 per meson.build:56); matches deployed /usr/local/src/umbriel-git/repo
  - id: wlroots-src
    resource: https://gitlab.freedesktop.org/wlroots/wlroots/-/tree/0.20.2
    title: wlroots 0.20.2 types/wlr_keyboard.c + types/seat/wlr_seat_keyboard.c (shallow clone inspected at .test-agent/key-repeat/wlroots-0.20.2; system package wlroots0.20 0.20.2)
  - id: deployed
    resource: /usr/local/share/umbriel/config.toml
    title: Deployed default config ([input.keyboard] at lines 219-227); live session verified via /run/user/1000/umbriel-wayland-1.sock (`umbriel submap` succeeded)
---

# Stage

The user wants to bump keyboard key repeat **live** while holding PageDown/PageUp
and restore it on release, without restarting the umbriel session. The
umbriel-side pipeline and per-key ramp patch are covered by companion waves;
this doc answers one narrow question: **what can change a running umbriel's
behavior at runtime, does any of it reach keyboard repeat settings, and what is
the most realistic live bump/restore loop?** All file:line citations are
against the pinned revision unless marked as deployed-config lines.

# Verdict up front

1. **Yes, umbriel has real live reload** — three independent triggers, all
   landing in one `Server::handleConfigReload()` path. No SIGHUP, no restart.
2. **Yes, reload re-applies `[input.keyboard]` repeat settings** to every
   already-connected physical keyboard: the input diff sets
   `ConfigEffects::input`, which calls `Keyboard::applyConfig()` →
   `wlr_keyboard_set_repeat_info()` on each live keyboard.
   Session and windows are untouched.
3. **Yes, wlroots 0.20 propagates it to focused clients**: changing repeat
   info emits a signal that the seat forwards as `wl_keyboard.repeat_info` to
   **all** seat clients immediately (verified in 0.20.2 source). This gates the
   whole approach, and it passes.
4. **No, keybinds cannot implement the loop** — a matched bind *consumes* the
   key (PageDown would never reach apps), and there are no on-release binds.
5. **Recommended loop: tiny IPC action patch** (`umbriel msg
   input-repeat-rate:<hz>`, ~60-90 LoC) driven by kanata's TCP notifications
   (the observer the [kanata wave](/design/key-repeat/kanata-repeat.glm53.md)
   already designed). A **zero-patch variant works today** by rewriting a
   small optional include file and letting inotify reload do the rest
   (~150 ms debounce; heavier reapply per bump).

# 1. How umbriel loads config

- **Path selection** (`-c` overrides): first existing of
  `$XDG_CONFIG_HOME|~/.config/umbriel/config.toml`, then each dir in
  `$XDG_CONFIG_DIRS|/etc/xdg` + `umbriel/config.toml`
  ([config.cpp:246-255](https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/src/config/config.cpp#L246-L255),
  [config.cpp:286-330](https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/src/config/config.cpp#L286-L330)).
  First-found wins; **umbriel does not auto-layer** candidates.
- **Include chain**: `include.files` (required, warning if missing) and
  `include.optional` (missing optional files are fine), expanded recursively
  with cycle/duplicate skip; deep merge where the including file's own content
  wins
  ([config_merge.cpp:234-262](https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/src/config/config_merge.cpp#L234-L262),
  [279-341](https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/src/config/config_merge.cpp#L279-L341)).
  The deployed `~/.config/umbriel/config.toml` is exactly this pattern: it
  includes `/usr/local/share/umbriel/config.toml` plus optional
  `keybinds-local.toml` / `animation.toml` (managed by umbriel.etc.pb).
- **Invalid config**: at startup umbriel refuses to start
  (main.cpp:324-327); on live reload it **keeps the previous configuration**
  and keeps watching the failed candidate
  (config.cpp:2609-2612, store.h:42; documented in
  [configuration.md:37-41](https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/docs/user/configuration.md#L37-L41)).
  Diagnostics surface in an on-screen panel and via `umbriel validate`
  (main.cpp:36-63).
- Watch set after each reload = every file whose change can affect the next
  reload, including included files and symlinks resolved to targets
  (store.h:31; config_watcher.cpp:95-110; re-armed at
  server_events.cpp:643-645).

# 2. Live reload exists — three triggers

All three land in [Server::handleConfigReload()
(server_events.cpp:616-646)](https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/src/server/server_events.cpp#L616-L646):

1. **inotify hot reload**: `ConfigWatcher` watches all config files, their
   directories, and symlink targets on the wl event loop
   ([server.cpp:804](https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/src/server/server.cpp#L804),
   config_watcher.cpp). Events include `IN_CLOSE_WRITE`/`IN_MOVED_TO`/etc
   (config_watcher.cpp:139-145), so atomic write-then-rename is picked up.
   **150 ms debounce timer** before reload (config_watcher.cpp:215).
2. **Keybind action** `config-reload` (keybind_parse.cpp:198 →
   actions.cpp:478-481).
3. **IPC**: `umbriel msg config-reload` — the `msg` command parses the same
   action table and executes it (ipc_commands.cpp:586-594). Unix socket at
   `$XDG_RUNTIME_DIR/umbriel-$WAYLAND_DISPLAY.sock` (ipc.cpp:107-112);
   the CLI honors `UMBRIEL_SOCKET` or builds the same path
   (ipc_client.cpp:21-27). Verified live on this host:
   `/run/user/1000/umbriel-wayland-1.sock` answered `umbriel submap`.

No SIGHUP handler exists (only SIGINT/SIGTERM on the event loop, SIGCHLD
ignored — main.cpp:330-333). There is **no dedicated `umbriel reload`
subcommand** and no set-config IPC; the IPC surface is `msg <action>` plus
read-only queries (`windows`, `workspaces`, `submap`, `layers`, `color`,
`tearing`, `keyboard-layouts`, `output-create/destroy` —
ipc_commands.cpp:616-629) and an event `subscribe` stream
(`theme, overview, keyboard_layout, windows, workspaces, submap` — ipc.h:34-36;
no input events).

# 3. What reload re-applies: yes, keyboard repeat is covered

Reload is **diff-driven, not full re-init**: the parsed config is compared to
the active one (`ConfigChange` sections, change.cpp:242
`.input = before.input != after.input`) and mapped to `ConfigEffects`
(change.cpp:275/307 `add(input, "input")`; effects struct at change.h:64-105).
Only invalidated subsystems re-apply.

For input:
[Server::applyConfig() effects.input](https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/src/server/server_events.cpp#L512-L534)
iterates **every existing keyboard** → `Keyboard::applyConfig()`
([keyboard.cpp:56-91](https://github.com/noctalia-dev/umbriel/blob/71291ac76737c1e6523c55899962c6ee6afcf7ad/src/input/keyboard.cpp#L56-L91)),
which resolves global vs per-device settings
(`input.findDevice(m_deviceName)`, keyboard.cpp:60-64; per-device
`repeat_rate`/`repeat_delay` overrides exist — config.h:850-851, deployed
config lines 270-273) and calls `wlr_keyboard_set_repeat_info()` at
keyboard.cpp:79. Virtual keyboards are skipped (keyboard.cpp:49-50).

So: **editing repeat_rate in any file of the include chain (or touching the
file) live-applies to the already-connected keyboard within ~150-250 ms, no
session restart, no focus loss** (focus preservation documented in
configuration.md:42-44; outputs/layouts/workspaces only re-apply if their own
sections changed). `umbriel msg config-reload` forces the same path on demand.

Cost per reload: `Keyboard::applyConfig()` rebuilds the xkb keymap
unconditionally (keyboard.cpp:65-77) and re-applies pointers/tablets/seat —
fine at human reload frequency, noticeable if bumped per keypress.

# 4. wlroots 0.20 propagation — verified

From the actual 0.20.2 tree (gitlab clone, tag `0.20.2`):

- [`wlr_keyboard_set_repeat_info()`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/wlr_keyboard.c#L288-L296):
  **no-op if values are unchanged** (so rewriting the same value does not spam
  clients), otherwise stores and emits `kb->events.repeat_info`.
- [`types/seat/wlr_seat_keyboard.c:100-108`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/seat/wlr_seat_keyboard.c#L100-L108):
  the seat listens for that signal and sends `wl_keyboard.repeat_info` to
  **all** seat clients (not just the focused one); also sent on keyboard bind
  (line 156). Keymap resend is guarded by an actual-change check (lines 126-128).

Caveat: `wl_keyboard.repeat_info` is a protocol state update; **uptake is
client-side**. Whether a toolkit re-arms its in-flight repeat timer at the new
rate mid-hold, or only at the next keypress/focus, is toolkit-dependent and
unverified (see Unresolved questions). Compositor-side bind-repeat
(`Keyboard::armRepeat`, keyboard.cpp:402-423) snapshots `repeat_info.rate` at
keydown, so compositor-repeated *bind actions* would not accelerate mid-hold.

# 5. Why keybinds cannot do the loop (the dead end)

- **Binds consume**: a matched press inserts the keycode into
  `m_consumedKeycodes` and never forwards (keyboard.cpp:311-324, 347); the
  release path only erases the bookkeeping entry (keyboard.cpp:356-358); the
  client-forwarding branch runs only `if (!handled)` (keyboard.cpp:372-380).
  A bound PageDown is invisible to applications. There is no
  pass-through-and-also-act bind mode.
- **No release binds**: `Keybind` has no on-release trigger
  (keybind_parse.h:214-231). The only release-driven action is the
  modifier-only tap (keyboard.cpp:358, 380-384). `spawn` runs keydown-only
  (actions.cpp:458).
- `repeat = true` on a bind re-fires the *action* while held; it does not
  forward key events to clients (keyboard.cpp:402-423).
- The `[events]` section is lid_close/lid_open commands only (config.cpp:1473-1477)
  — no key hooks.

Conclusion: a compositor-only, no-source-change version of the loop does not
exist. The key observation must come from below umbriel — which on this host
means kanata, which already grabs all real keyboards and re-emits on a uinput
"kanata" device, and already has the TCP notification design
([kanata wave](/design/key-repeat/kanata-repeat.glm53.md)). Note the umbriel
device that repeat settings apply to is that uinput "kanata" board, so
per-device targeting (`[input.keyboard."kanata"]`) is possible if the pedal
boards should keep stock behavior.

# 6. Ranked options for the live bump/restore loop

**Option A (recommended): tiny `input-repeat-rate` msg action + kanata TCP observer.**
Add an IPC/keybind action that sets repeat on live keyboards directly, skipping
config round-trips:

- `src/config/keybind_parse.h`: new `KeybindAction::InputRepeatRate` enum
  member (enum at keybind_parse.h:~75) + a small payload struct appended to the
  `KeybindPayload` variant (keybind_parse.h:209-212) + an `ActionSpec` row
  (ActionSpec shape at keybind_parse.h:269-279).
- `src/config/keybind_parse.cpp`: spec row next to the `config-reload` row
  (line 198) + `parseAction` branch (line 463).
- `src/server/actions.cpp`: handler next to `actionConfigReload` (line 478)
  + entry in `kActionHandlers` (line 1708).
- `src/server/server.{h,cpp}`: `Server::setKeyboardRepeat(int hz)` iterating
  `m_keyboards` (server.h:747, private — hence the method), skipping virtual,
  calling `wlr_keyboard_set_repeat_info()`.

~60-90 LoC across 4 files; latency ≈ one IPC round-trip; no file churn, no xkb
rebuild (calls wlroots directly). The helper daemon: kanata TCP notification on
pgdn press → `umbriel msg input-repeat-rate:120`; release → `umbriel
msg input-repeat-rate:25`. Semantics: transient override — the next config
reload legitimately restores config values; the helper should treat config as
the source of truth for the resting rate (that is exactly what it wants).

**Option B (works today, zero source patch): rewrite an optional include file.**
Once (umbriel.etc.pb): add `repeat-boost.toml` to the root config's
`include.optional`. The helper: on pgdn press, atomically write
`repeat-boost.toml` containing `[input.keyboard]\nrepeat_rate = 120`; on
release, rewrite with `25` (or truncate — missing optional includes are fine,
config_merge.cpp:318-321). inotify + 150 ms debounce → diff → input reapply →
repeat_info resend. Honored constraints: watcher handles atomic rename
(config_watcher.cpp:139-145) and symlinked paths; failed writes keep the old
config. Costs/risks: every bump re-applies the whole input subsystem including
an xkb keymap rebuild per keyboard; ~150-250 ms latency; repeat writes churn
the diagnostics pipeline for no reason. Realism: **workable prototype today;
not the long-term shape**.

**Option C: in-compositor per-key ramp.** The cleanest UX (zero external
daemons, per-key ramp curve) is the compositor patch the sibling
[umbriel-repeat wave](/design/key-repeat/umbriel-repeat.glm53.md) is designing;
this doc's §3-4 give it the two facts it needs (reload already re-applies
repeat live; wlroots resends repeat_info on change), and Option A's
`Server::setKeyboardRepeat` is the same Server method that patch would drive
internally.

**Dead end (documented so nobody retries):** keybind/hook-based observation
inside umbriel — §5.

Realism ranking: **A > C > B** for the final host; **B first** if we want to
feel the behavior this week — it is pure config + a ~50-line helper.

# Risks

- **Client uptake of mid-hold `repeat_info` changes is unverified.** wlroots
  definitely delivers the event; GTK/Qt/Electron/kitty behavior while a key is
  already repeating may vary (re-arm each cycle vs snapshot at press). Cheap
  empirical test: set `repeat_rate = 5` in user config, hold a key in a text
  field, run `umbriel msg config-reload` after writing `40`, watch.
- Option B's full input reapply per bump includes keymap rebuild — verify it
  does not disturb held-modifier state or numlock under rapid toggling
  (`applyConfig` → `wlr_keyboard_set_keymap` resets xkb_state; wlroots only
  resends the keymap to clients if it actually changed).
- IPC socket path varies with `WAYLAND_DISPLAY` (here `wayland-1`); helpers
  should honor `UMBRIEL_SOCKET` (ipc_client.cpp:21-22).
- Config reload failure keeps the previous config silently applied (only log
  + panel); a broken helper write could stall boosts without an error channel
  toward the helper. `umbriel validate` exists for pre-flight (main.cpp:36-63).
- Repeat is one of three races on this host (hardware EV_REP passthrough via
  kanata, umbriel/wlroots, client-side) — see the kanata wave's "three races"
  analysis before attributing observed behavior.

# Unresolved questions

- Toolkit uptake of mid-hold repeat_info changes (the empirical test above).
- Does umbriel's libinput seat hold EVIOCGRAB on the kanata uinput device such
  that no other reader can snoop it (making kanata TCP the only observer
  lane)? Likely, unverified.
- Would upstream take an `input-repeat-rate` action, or is a
  `wlr-virtual-pointer`-style "input state" IPC group a better ask?
- Exact device name umbriel reports for the kanata uinput board (for
  per-device targeting); `umbriel msg` has no device listing action — check
  logs or `libinput list-devices` equivalent.
- Sibling [umbriel-repeat.glm53.md](/design/key-repeat/umbriel-repeat.glm53.md)
  was in flight at write time; reconcile Option A's `Server::setKeyboardRepeat`
  with its pipeline design when it lands.

# Cross-references

- [`design/key-repeat/kanata-repeat.glm53.md`](/design/key-repeat/kanata-repeat.glm53.md)
  — the observer lane and the full repeat-races stack analysis; its kanata
  layer-edge TCP notifications are the trigger source for Options A/B here,
  and it pre-cites this doc.
- [`design/key-repeat/umbriel-repeat.glm53.md`](/design/key-repeat/umbriel-repeat.glm53.md)
  — companion umbriel pipeline + per-key ramp patch (in flight); Option A's
  Server method is shared machinery with it.
- [`design/kanata-source/cutover0.glm53.md`](/design/kanata-source/cutover0.glm53.md)
  and [`design/kanata-devices/init0.glm53.md`](/design/kanata-devices/init0.glm53.md)
  — why the compositor-visible keyboard is kanata's uinput device.
- [`umbriel.src.pb`](/umbriel.src.pb) / [`umbriel.etc.pb`](/umbriel.etc.pb) —
  build and config deployment whose include-chain root (§1) an Option B
  `repeat-boost.toml` would slot into.
