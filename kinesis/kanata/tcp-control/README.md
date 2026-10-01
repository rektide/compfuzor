# TCP-control implementation checkpoint

Main operator guide: [Kanata alternatives](/doc/kinesis/kanata.md);
directory entry point: [Kinesis](/kinesis/README.md). These are alternatives,
not additions to the existing Edge/pedal owners. No live service was changed.

| Playbook | Unit | Role |
| --- | --- | --- |
| [keyboard.srv.pb](/kinesis/kanata/tcp-control/keyboard.srv.pb) | `kanata-a-keyboard` | Exact Edge keyboard; F19/F20 directly execute helper with pages/media argv |
| [keyboard-hotkeys.srv.pb](/kinesis/kanata/tcp-control/keyboard-hotkeys.srv.pb) | `kanata-a-keyboard-hotkeys` | Same device/layout, packaged binary; emits F19/F20 for compositor bindings |
| [pedal.srv.pb](/kinesis/kanata/tcp-control/pedal.srv.pb) | `kanata-a-pedal` | Exact BlueTurn; private TCP listener on `127.0.0.1:16666` |
| [build.src.pb](/kinesis/kanata/tcp-control/build.src.pb) | none | Separate source checkout/build; explicit build invocation, private real binary copy |

SmartSet prerequisites: `[hk3]>[f19]`, `[hk4]>[f20]`, `[hk5]>[f21]`,
`[hk6]>[f22]`; refresh and disconnect v-Drive. Caps remains
`(tap-hold 100 100 esc lctl)`, F21/F22 become lalt/lmet. Both keyboard
variants own only `Kinesis Freestyle Edge RGB Keyboard`, not Consumer Control.
Pedal uses mode 2 (LEFT pgup / RIGHT pgdn). First layer `pages` is the startup
default; TCP selects `pages` or `media`. In pages, LEFT hold overlays
`pedal-meta`, RIGHT becomes play/pause. Media is plain prev/next with no held
overlay activation. Release pedals before changing defaults: held-overlay
transitions have not been hardware-tested. `_` falls through the active default;
it is not another ChangeLayer target.

### Compositor bindings (hotkeys variant)

For Sway, add these bindings to its config after deliberately staging the
hotkeys helper and starting the pedal alternative:

```sway
bindsym F19 exec /etc/opt/kanata-a-keyboard-hotkeys/blueturn-switch pages
bindsym F20 exec /etc/opt/kanata-a-keyboard-hotkeys/blueturn-switch media
```

For KDE Plasma, create two command shortcuts in System Settings → Keyboard →
Shortcuts: assign F19 to
`/etc/opt/kanata-a-keyboard-hotkeys/blueturn-switch pages` and F20 to
`/etc/opt/kanata-a-keyboard-hotkeys/blueturn-switch media`. Remove conflicting
bindings and ensure SmartSet emits these keys. This variant uses no Kanata
`cmd` action; the desktop session executes the helper.

## Rendering and checking

Run from repository root; symlinks `vars`, `roles`, `files` expose the three
framework loader roots. The helper lives separately under `scripts/`, referenced
by absolute `playbook_dir` in ETC_FILES, copied executable outside `/home` on
deployment. `raw: true` avoids treating Python as an Ansible template. Ansible
file lookup strips its final newline, otherwise staged bytes match.

```sh
for p in keyboard.srv keyboard-hotkeys.srv pedal.srv build.src; do
  ansible-playbook kinesis/kanata/tcp-control/$p.pb --syntax-check
done
# Repo download is disabled by the render-only profile. Supply an empty
# source directory so the framework's repo exposure link can be rendered.
mkdir -p .test-agent/kinesis-kanata/render/src/kanata-a-build/source
for p in keyboard.srv keyboard-hotkeys.srv pedal.srv build.src; do
  ansible-playbook -i 'localhost,' -c local kinesis/kanata/tcp-control/$p.pb \
    -e @kinesis/kanata/shared/render-only.yaml
done
python3 kinesis/kanata/tcp-control/tests/check-render.py
python3 kinesis/kanata/tcp-control/tests/test-blueturn-switch.py
kanata --check --cfg .test-agent/kinesis-kanata/render/etc/kanata-a-pedal/kanata.kbd
kanata --check --cfg .test-agent/kinesis-kanata/render/etc/kanata-a-keyboard-hotkeys/kanata.kbd
```

Verified: four syntax checks; all four scratch renders; real rendered config,
unit, helper and link-only installer assertions; seven fake-loopback helper
tests; generated build script `bash -n`; packaged Kanata 1.9.0 `--check` passes
pedal/hotkeys. Direct keyboard config **cannot be checked by packaged Kanata**:
it rejects `cmd`. Packaged help also lacks `--port`.

## Private build and remaining verification

Source pin: upstream stable [`v1.12.0`](https://github.com/jtroo/kanata/tree/v1.12.0),
commit `02242ef761ef43b860eac30067ce86904be7d466`. Local archive was inspected
first. Build uses a separate checkout, not archive refresh/workspace mutation,
and no global binary exposure. After deliberately rendering/deploying the build
playbook with prerequisites available, its generated script is explicitly run:

```sh
/usr/local/src/kanata-a-build/bin/build-kanata.sh
/usr/local/src/kanata-a-build/bin/kanata --check --cfg /etc/opt/kanata-a-keyboard/kanata.kbd
/usr/local/src/kanata-a-build/bin/kanata --check --cfg /etc/opt/kanata-a-pedal/kanata.kbd
```

Cargo/Rust must already be available. A scratch source export of the local tag
was attempted with `cargo build --locked --offline --bin kanata
--no-default-features --features tcp_server,cmd`. It stopped at missing crates.io
metadata for `karabiner-driverkit`, before compiling. Logs are in
`.test-agent/kinesis-kanata/tcp-cargo.log`; private-binary parsing and actual
TCP-to-pedal behavior remain unverified. No devices, services, package state or
sudo operations were exercised.

## Architecture and evidence

- `vars_files` has higher precedence than ordinary play vars. TCP plays load
  common defaults then freeze `KANATA_SERVICE_BASE | combine(...)` as a fact
  before framework unit generation; plain play overrides silently lose.
- TCP server and direct cmd client share host loopback (`PrivateNetwork=no`),
  restrict AF_UNIX/AF_INET, allow localhost over deny-any. PrivateUsers stays on.
  The hotkeys daemon retains private networking; compositor helper runs outside
  it. The TCP endpoint has no authentication: any allowed local process can
  change layers. It is not a durable mode store or an acknowledged transaction.
- Default virtual output name `kanata` is preserved because upstream
  [`is_input_device`](https://github.com/jtroo/kanata/blob/v1.12.0/src/oskbd/linux.rs)
  skips exactly it; distinct units provide observability instead.
- [`Cargo.toml`](https://github.com/jtroo/kanata/blob/v1.12.0/Cargo.toml)
  defines `tcp_server` and `cmd` features; both are explicitly built.
- [`ClientMessage`](https://github.com/jtroo/kanata/blob/v1.12.0/tcp_protocol/src/lib.rs)
  defines ChangeLayer JSON; helper sends one newline-terminated line using
  stdlib sockets, never shell interpolation. A successful send is not proof
  that the server applied the layer.
- [`change_layer`](https://github.com/jtroo/kanata/blob/v1.12.0/src/kanata/mod.rs)
  sets the named default layer and silently ignores unknown names. Helper's
  two-value allowlist prevents accidental unknown targets.
- [`cmd`](https://github.com/jtroo/kanata/blob/v1.12.0/src/kanata/cmd.rs)
  uses direct argv execution;
  [`main.rs`](https://github.com/jtroo/kanata/blob/v1.12.0/src/main.rs)
  `--check` parses config then exits before device setup. ExecStartPre gates
  config parsing/binary existence; feature checks must still follow this guide.

Shared defaults install link-only, without enable/start or aliases. They do not
automatically stop existing device owners; switching and cleanup stay deliberate.
