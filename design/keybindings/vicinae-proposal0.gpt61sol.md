---
type: CutoverProposal
title: Minimal Vicinae and Umbriel declaration cutover
description: Proposed declarations and deliberate root adoption after generated installer proof; no live playbook changes are applied.
resource: /design/keybindings/vicinae-proposal0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-01 }
verified: { by: unverified }
stale_after: 2026-11-01
sources:
  - resource: /examples/keybindings/vicinae.yaml
    title: Executable declaration fixture
  - resource: /vicinae.src.pb
    title: Existing source builder and native/installer duplication
  - resource: /umbriel.user.pb
    title: Existing user root and personal policy
  - resource: https://github.com/vicinaehq/vicinae/blob/main/src/server/src/ipc/ipc-command-handler.cpp
    title: Locally inspected modern launch routing
---

# Gate and exact changes proposed

The automatic declaration/installer path is implemented and tested in isolated
consumers. This proposal is **not** a live cutover and does not change existing
source-building playbooks. The parent should read these values before authorizing
their adoption.

For [`vicinae.src.pb`](/vicinae.src.pb):

1. Add the named `KEYBINDING_ACTIONS` and `KEYBINDINGS` from the
   [executable fixture](/examples/keybindings/vicinae.yaml).
2. Bind explicit user consumer profiles rather than discovering compositors:

   ```yaml
   KEYBINDING_TARGETS:
     niri:
       consumer: /opt/desktop/etc/keybinding-niri.json # actual adopted host binding required
       context: user
       scope: user
     umbriel:
       consumer: "${XDG_CONFIG_HOME}/umbriel/keybinding-umbriel.json"
       context: user
       scope: user
   ```

   The latter is resolved at invocation with the existing CONFIG selector helper;
   packaged system producer paths remain absolute system paths.
3. Remove only the three hand-authored Niri fragments, the single Umbriel fragment,
   and their two bespoke `install-niri.sh`/`install-umbriel.sh` bodies. Generation
   supplies one source file per declaration and shared user-scoped target entries.
4. Preserve source repository/build/system-install/service bodies and **every KDE
   resource/installer** unchanged. The new target entries belong to user install
   aggregation; they do not become extra system build/install operations.

For [`umbriel.user.pb`](/umbriel.user.pb):

```yaml
KEYBINDING_CONSUMERS:
  umbriel:
    contexts:
      user: {scope: user, root: config, subpath: umbriel}
    baseline: [/usr/local/share/umbriel/config.toml]
    personal: [keybinds-local.toml, animation.toml]
    registration: link
    placement: link
KEYBINDINGS:
  vicinae-clipboard:
    patch: true
    umbriel: {keys: [Mod+Grave]}
```

The user clipboard patch supplies only the chord. It references the producer's
named binding/action and stays dormant if that producer is absent or disabled.
Once adopted, remove the duplicate command-valued `Mod+Grave` entry from
[`keybinds-local.toml`](/files/umbriel/keybinds-local.toml); leave every other
personal chord and animation setting unchanged.

# Readable root adoption

Deliberately adapt [`files/umbriel/config.toml`](/files/umbriel/config.toml) to one
required array insertion area, baseline first, personal files late:

```toml
[include]
files = [
  "/usr/local/share/umbriel/config.toml",
  # compfuzor-keybindings-begin
  # compfuzor-keybindings-end
]
optional = { files = ["keybinds-local.toml", "animation.toml"] }
```

Remove the hardcoded Vicinae include deliberately as part of this adoption, not
by filesystem pruning. Existing old physical files can remain excluded. Native
validation must check the complete proposed root before activation.

The current playbook rewrites root content on every render. Change its root
artifact to an explicit seed (`name: config.toml, once: true`) or equivalently
stop the filesystem writer from subsequently overwriting the managed area. This
is a consequential policy choice: source template changes do not silently replace
an already adopted user root. Later template updates require deliberate adoption
or refresh. Personal fragments can retain their current writer policy.

For Niri, adopt an insertion area in the chosen root while preserving existing
baseline and late personal text. No current Niri root is silently transformed by
this proposal. The host profile path above is a placeholder until the operator
chooses the actual consumer binding.

# Chords and command parity

| Binding | Niri suggestion | Umbriel policy |
|---|---|---|
| Launcher | `Mod+D` | `Mod+Space` |
| Clipboard | `Alt+Grave` | User patch `Mod+Grave` |
| Switch windows | `Mod+F` | `Mod+Slash` |

**Proposed command choice:** shared modern `vicinae deeplink
vicinae://launch/<provider>/<entrypoint>` routes. Preserve current intentional
toggle differences: Niri uses the open route without `toggle`; Umbriel retains
`?toggle=true` for clipboard and switch-windows. Launcher remains `vicinae toggle`.
This is complete argv replacement under the target action specifier, not generic
argument-array concatenation.

Primary-source verification came from the local archived Vicinae checkout first:

- [CLI deeplink command](https://github.com/vicinaehq/vicinae/blob/main/src/cli/src/cli.cpp#L409-L424)
  accepts the explicit URI and sends it through IPC.
- [Launch routing](https://github.com/vicinaehq/vicinae/blob/main/src/server/src/ipc/ipc-command-handler.cpp#L117-L182)
  implements `toggle=true`, provider lookup and `<provider>/<entrypoint>` activation.
- [Clipboard provider](https://github.com/vicinaehq/vicinae/blob/main/src/server/src/builtins/clipboard/clipboard-extension.hpp#L8-L13),
  [history command](https://github.com/vicinaehq/vicinae/blob/main/src/server/src/builtins/clipboard/clipboard-history-command.hpp#L8-L13)
  and registration identify `clipboard/history`.
- [WM provider/command](https://github.com/vicinaehq/vicinae/blob/main/src/server/src/builtins/wm/wm-extension.cpp#L86-L94)
  plus its `id()` at line 127 identify `wm/switch-windows`.

This verifies route and entrypoint semantics in source. The test renders and
native-validates configuration; it **does not** launch Vicinae or claim a live UI
behavior test. Legacy direct-URI CLI compatibility exists, but the old
`extensions/vicinae/...` spelling is not the interface to perpetuate here.

# Proof and remaining choice

[`keybindings_vicinae_proposal.test.py`](/tests/integration/keybindings_vicinae_proposal.test.py)
uses the actual example values, real generated installers and stock CONFIG worker
artifacts in isolated HOME/XDG consumers. It checks the six target chord outcomes
and retained target-specific toggle policy without calling the applications.

Before actual cutover, the parent/operator still selects the real Niri host path
and deliberately adopts both roots. The implemented declarations and shared
runtime do not authorize live deployment, reload or unrelated cleanup.

# Cross-references

- [Producer guide](/doc/config/keybinding-producers.md): exact authoring,
  system/runtime path separation, source registration versus native placement.
- [Consumer guide](/doc/config/keybinding-consumers.md): insertion scope,
  context-aware validation and publication constraints retained here.
- [Prior consumer checkpoint](/design/keybindings/implementation1.gpt61sol.md):
  accepted implementation seam; this proposal is the narrowly scoped client adoption.
