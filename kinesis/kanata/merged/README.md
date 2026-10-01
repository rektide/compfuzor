---
type: Notes
title: Option B — merged keyboard+pedal kanata instance
description: One kanata layout owning both the Freestyle Edge RGB and the BlueTurn, with layer-switch pedal pages.
tags: [kinesis, kanata, blueturn, layers, smartset]
status: draft
generated: { by: "model:glm-5.3-flash", at: "2026-10-01" }
sources:
  - resource: /doc/kinesis/kanata.md
    title: Parent guide — Kinesis and BlueTurn, kanata by example
  - resource: /kanata-blueturn.srv.pb
    title: Current pedal mapping (semantics preserved here)
  - resource: /kinata.srv.pb
    title: Current Edge mapping (Game Bank prerequisite)
---

# Option B — merged keyboard + pedal instance

[`keyboard-pedal.srv.pb`](keyboard-pedal.srv.pb) runs **one** kanata instance
(unit `kanata-b-merged.service`, link-only) that owns exactly two evdev nodes:

- `Kinesis Freestyle Edge RGB Keyboard` (the keyboard node; the `…Consumer
  Control` node is a different exact name and stays with main)
- `iRig BlueTurn Keyboard`

Because both devices feed one keymap, a SmartSet-programmed Game Bank key can
switch the base layer the **pedal** types into — a plain
`(layer-switch …)`, no TCP helper, `cmd` builds, or desktop shortcuts (that is
option A, [`../tcp-control/`](../tcp-control/README.md)).

## Shape of the layout

```text
defsrc   caps   f19       f20       f21   f22   pgup            pgdn
         │      hk3       hk4       hk5   hk6   pedal L / kbd   pedal R / kbd
         ▼      ▼         ▼         ▼     ▼     ▼               ▼
pages    cap→esc/ctrl  @pages  @media  lalt  lmet  tap pgup / hold→meta  pgdn
media    cap→esc/ctrl  @pages  @media  lalt  lmet  prev            next
```

- `pages` is the default base: the current main caps remap plus the current
  pedal semantics (tap LEFT = PageUp, hold LEFT ≥ 180 ms = `pedal-meta`
  overlay, RIGHT = PageDown; RIGHT tap inside the overlay = play/pause).
- `media` is the second base: LEFT = previous track, RIGHT = next track.
- `f19`/`f20` are **persistent** selectors (`layer-switch`): the choice sticks
  until the other is chosen and affects subsequent presses only. `f21`/`f22`
  are held Alt / Windows modifiers on every page.

## The two kanata layer traps this example teaches

**Switched bases must repeat everything.** `_` on a `layer-switch`ed base falls
through the stack straight to `defsrc` (`delegate-to-first-layer` is not
enabled) — it does **not** mean "whatever the first layer did". A `_` in
`media` would emit raw F19/F20/F21/F22 and raw Caps: the modifiers, selectors
and the caps remap would silently vanish on every page but the first. So both
bases repeat `@cap`, `@pages`, `@media`, `lalt`, `lmet` explicitly. See the
[transparent-key semantics](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#transparent-key)
in the kanata guide.

**Held overlays delegate for free.** `pedal-meta` is a `layer-while-held`
overlay, which sits *above* whichever base is active. There `_` is correct and
desirable: selectors, modifiers and caps keep working while the overlay is
held, whatever page you are on. Only its RIGHT column (`pp`) overrides.

## The collision (why B is an alternative, not an upgrade)

Kanata 1.9 on Linux has no per-device keymaps, so both devices share columns
and state:

- **Column sharing** — the Edge's physical PgUp/PgDn keys are the *same
  columns* as the pedals. In `pages` a physical PgUp tap pages back and a
  physical PgUp **hold** opens `pedal-meta`; in `media` both physical keys
  become prev/next. The pedal can also reach those columns in either page.
- **Shared timing/history** — timers, input history and idle are shared, not
  per-device. Plain `tap-hold` here is timeout-based and need not resolve early
  on another keypress. Extensions using `tap-hold-press`/`-release` or one-shots
  can be resolved/consumed by input from either device.
- **Output name invariant** — kanata's Linux autodetect skips only the literal
  output name `kanata` (`src/oskbd/linux.rs`, `is_input_device`). This variant
  deliberately sets no `linux-output-device-name`: renaming its output would
  make the always-running main instance re-grab and reprocess it. Instances
  are told apart by unit name and journal tag, which is sufficient here.

## SmartSet prerequisite (manual; kinefolk's job)

The Game Bank is factory-blank: hk3–hk6 emit nothing until programmed. In the
active profile's `layouts/layoutN.txt` (SmartSet+F8 opens the v-Drive, which is
optionally mounted at `/mnt/kinesis` if [`kinesis.etc.pb`](/kinesis.etc.pb)
has been deployed):

```text
[hk3]>[f19]     [hk4]>[f20]     [hk5]>[f21]     [hk6]>[f22]
fn [hk3]>[f19]  fn [hk4]>[f20]  fn [hk5]>[f21]  fn [hk6]>[f22]
```

The `fn` rows keep the keys' identity while the hardware Fn layer is held.
Full walkthrough and cautions (back up the profile, remove conflicting
recorded macros, refresh, close the v-Drive before testing):
[`/doc/kinesis/kanata.md`](/doc/kinesis/kanata.md). These playbooks never
write the v-Drive.

## Rendering and checking — nothing live

From the Compfuzor checkout root:

```sh
ansible-playbook kinesis/kanata/merged/keyboard-pedal.srv.pb --syntax-check
./kinesis/kanata/merged/check.sh   # renders to scratch, then kanata --check + invariants
```

`check.sh` drives the shared scratch profile
([`../shared/render-only.yaml`](../shared/render-only.yaml)): artifacts land in
`.test-agent/kinesis-kanata/render/`, with packages, repos, modules, links,
bin runs and systemd enable/start all bypassed. It then validates the rendered
`kanata.kbd` with the installed `kanata --check` and asserts the invariants
that matter (explicit caps/selector/modifier repeats in *both* bases; no
`linux-output-device-name`; ExecStart pointed at the staged config, not
`/etc/kanata`).

## Switching variants on a live host

The `roles`, `vars`, and `files` symlinks expose root framework resources to
this nested playbook: role lookup and `include_defaults` resolve from the
playbook directory, so the relative task import alone is insufficient.

Stop `kanata-kinata`, `kanata-blueturn` (and any option-A services) before
starting `kanata-b-merged` — two consumers of one evdev node never run
concurrently. Main (`kanata.srv.pb`) already excludes both device names and
can stay up. Nothing here enables anything at boot; revisit
[`/doc/kinesis/kanata.md`](/doc/kinesis/kanata.md#deliberate-variant-switching)
for the full matrix and release-the-pedals-first notes.

## Cross-references

- [`/doc/kinesis/kanata.md`](/doc/kinesis/kanata.md): parent guide — the
  B section motivates this design and its cost.
- [`/kanata-blueturn.srv.pb`](/kanata-blueturn.srv.pb): the pedal semantics
  (tap-hold, `pedal-meta`, `pp`) this variant preserves verbatim.
- [`/kinata.srv.pb`](/kinata.srv.pb): the Edge semantics (caps remap,
  F21/F22→Alt/Win) this variant preserves and extends with selectors.
- [`/design/blueturn/blueturn-linux-research.general.md`](/design/blueturn/blueturn-linux-research.general.md):
  pedal transport caveats (kernel short-report regression) — an unresponsive
  pedal here is transport, not layering.
- [`../tcp-control/README.md`](../tcp-control/README.md): option A, which
  solves the shared-identity cost with two instances and IPC.
- [kanata `layer-switch` / `layer-while-held` reference](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#layer-while-held):
  authoritative layer-stack semantics behind the repeat-everything rule.
