# Kinesis examples

Hardware-specific alternatives live here; current root playbooks remain unchanged.
These examples are **alternatives, not a bundle to run simultaneously**.

## Kanata

- [Example guide](/doc/kinesis/kanata.md): device ownership, layer semantics,
  SmartSet prerequisites, safe rendering, and explicit variant switching.
- [TCP control (A)](/kinesis/kanata/tcp-control/README.md): separate keyboard and
  BlueTurn services; direct command and compositor-hotkey triggers.
- [Merged layout (B)](/kinesis/kanata/merged/README.md): one engine receives both
  devices; no IPC, but identical keycodes share meanings.
- [SmartSet alternatives](/kinesis/kanata/smartset/README.md): native passthrough,
  one-shot modifiers, and a momentary command layer.
- [Shared service defaults](/kinesis/kanata/shared/service.yaml): sandboxed,
  link-only units and staged config paths, without changing current services.

## Current setup

- [Main keyboard remapper](/kanata.srv.pb).
- [Edge Alt/Windows mapping](/kinata.srv.pb): hk5/F21 → Alt; hk6/F22 → Windows.
- [BlueTurn-only remapper](/kanata-blueturn.srv.pb): page turning plus a held
  play/pause layer.
- [Kanata source checkout](/kanata.src.pb).

SmartSet firmware-side control belongs to the separate `~/src/kinefolk` project.
The examples document that boundary; they do not rewrite the keyboard's v-Drive.

## Native configuration access

- [v-Drive mount](/kinesis.etc.pb): optional systemd mount/automount declarations
  for accessing the Edge's configuration volume; not an editor or remapper.
