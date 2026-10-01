# SmartSet alternatives

Choose **one** alternative; each owns only `Kinesis Freestyle Edge RGB Keyboard`.
All use the [shared sandbox](/kinesis/kanata/shared/service.yaml), unique units,
staged configs, and disabled enable/start. They never edit the v-Drive. Keep
the default virtual output name `kanata` so the main daemon skips it.

| Playbook | Unit | Behavior |
|---|---|---|
| [native](/kinesis/kanata/smartset/native.srv.pb) | `kanata-edge-native` | Native Alt/Windows pass through; caps tap Esc/hold Ctrl |
| [one-shot](/kinesis/kanata/smartset/one-shot.srv.pb) | `kanata-edge-one-shot` | Tap arms Alt/Windows for next key or 1000 ms; hold behaves normally |
| [command-layer](/kinesis/kanata/smartset/command-layer.srv.pb) | `kanata-edge-command-layer` | Hold hk7 for commands; hk5/6 stay held Alt/Windows |

## Exact manual SmartSet prerequisites

Merge the chosen assignments into the **active** `layouts/layoutN.txt`, backing
it up first. Use remaps with press/release, not recorded macros. Game Bank keys
are factory-blank: without programming, they do nothing.

Native:

```text
[hk5]>[lalt]
[hk6]>[lwin]
fn [hk5]>[lalt]
fn [hk6]>[lwin]
```

One-shot:

```text
[hk5]>[f21]
[hk6]>[f22]
fn [hk5]>[f21]
fn [hk6]>[f22]
```

Command layer:

```text
[hk1]>[f13]
[hk2]>[f14]
[hk3]>[f15]
[hk4]>[f16]
[hk5]>[f21]
[hk6]>[f22]
[hk7]>[f23]
[hk8]>[f24]
fn [hk1]>[f13]
fn [hk2]>[f14]
fn [hk3]>[f15]
fn [hk4]>[f16]
fn [hk5]>[f21]
fn [hk6]>[f22]
fn [hk7]>[f23]
fn [hk8]>[f24]
```

`fn` stabilizes identity on the **hardware** Fn layer. Open/close the v-Drive
with SmartSet+F8; refresh with SmartSet+Profile. Close it before testing.
Native programming belongs to manual Direct Programming or the in-progress
`~/src/kinefolk` project, not these playbooks. See the
[parent guide](/doc/kinesis/kanata.md#common-smartset-contract) for details.

## DSL lessons

- Native modifiers work without Kanata, but Game Mode can suppress Windows.
  Mediated variants instead produce F21/F22 without the remapper.
- `$modifier-timeout` substitutes data; `@alt-next` names an action.
  [One-shot](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#one-shot)
  is not `(macro lalt)`: that taps Alt, not a held modifier. Processing all
  unmapped keys lets ordinary typing consume the armed modifier.
- Release hk7 to leave `commands`. Its `_` entries delegate through a **held
  overlay** to base, unlike `_` on a switched base in
  [merged B](/kinesis/kanata/merged/README.md).
- Commands hk1..4 are Ctrl+C/V/Z/Shift+Z (copy/paste/undo/redo in many apps).
  hk8 types `hello` as ordered macro taps. Test in a disposable text field
  without Alt/Windows held. Outside commands these keys forward raw F keys.

## Non-live checks and nested paths

From the checkout root run `kinesis/kanata/smartset/check.sh`. It syntax-checks,
scratch-renders, validates actual configs with `kanata --check`, and inspects
units/installers. The [render profile](/kinesis/kanata/shared/render-only.yaml)
disables package installation, live links, device grabs and service activation.

`roles`, `vars`, and `files` symlinks expose root framework resources to nested
playbooks: role resolution and `include_defaults` use the playbook directory,
so the relative task import alone is insufficient.

Before live testing stop current `kanata-kinata` and competing Edge examples;
main and current BlueTurn can remain. See the
[switching matrix](/doc/kinesis/kanata.md#deliberate-variant-switching).

## Cross-references

- [Parent guide](/doc/kinesis/kanata.md): firmware/host boundary, syntax lessons,
  variant switching and hardware acceptance checks.
- [Current Edge playbook](/kinata.srv.pb): verified device identity and current
  held-modifier baseline; these alternatives leave it untouched.
- [Merged B](/kinesis/kanata/merged/README.md): persistent versus held layers,
  and shared keyboard/pedal input history.
