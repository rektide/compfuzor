---
type: Reference
title: Tmux plugin receivers and optional persistence
description: Ahiru and TPM CONFIG contribution blocks, separate persistence playbooks, and explicit session restoration without keybindings.
resource: /doc/tmux/README.md
status: active
generated: {by: 'model:openai/gpt-6-astra', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed1c3f231ffec43Dwg4C35l77Z
    title: Separate persistence from Ahiru and give Ahiru and TPM a shared remote CONFIG receiver
  - resource: /doc/config/definitions.md
    title: Complete named CONFIG definitions and selected-definition remote delivery
  - resource: https://github.com/tmux-plugins/tmux-resurrect/blob/master/resurrect.tmux
    title: Binding iteration and published save/restore script paths
  - resource: https://github.com/tmux-plugins/tmux-resurrect/blob/master/scripts/helpers.sh
    title: Empty binding options fall back to defaults
  - resource: https://github.com/tmux-plugins/tmux-continuum/blob/master/README.md
    title: Automatic-save interval, explicit restore enablement, and status-line ordering
  - resource: https://github.com/x3rAx/ahiru-tpm/blob/main/src/plugins/load.rs
    title: Parallel loading requires explicit sequencing for Continuum
---

# Tmux plugins

[Ahiru](/tpm-ahiru.src.pb) and [TPM](/tmux-tpm.src.pb) share the
[`tmux` CONFIG definition](/vars/tmux-plugins.yaml). Each manager owns its own
deployment and exposes `tmux/plugins` as a remote fragment input. Other complete
CONFIG definitions can coexist in that deployment.

Fragments in `etc/tmux-plugins.d/*.conf` assemble in filename order into attributed
blocks in `etc/tmux-plugins.conf`. The manager's `install-user.sh` publishes a link
under `$XDG_CONFIG_HOME/tmux/compfuzor/<NAME>/` (default `~/.config`) and adds a
`source-file` block before the manager initialization at the end of the user's
tmux config. Both managers can discover declarations through that explicit source.

Remote delivery rebuilds the canonical aggregate; the installed link sees the
updated content immediately. Loading it into tmux remains an explicit action.
See [CONFIG definitions](/doc/config/definitions.md#remote-input-delivery) for
selected-definition delivery, disabled inputs, and transaction semantics.

## Optional persistence

- [`tmux-resurrect.etc.pb`](/tmux-resurrect.etc.pb): save/restore engine, pane contents,
  snapshots under `~/.local/share/tmux/resurrect`, and `bin/restore-session.sh`.
- [`tmux-continuum.etc.pb`](/tmux-continuum.etc.pb): automatic saving every 15 minutes;
  **automatic restoration is off**. Requires Resurrect to be contributed too.

Resurrect's save/restore binding options contain a single space. Upstream treats
an empty string as “use defaults”; whitespace gives its binding loop zero keys.
No save or restore key is installed. The helper asks the running tmux server for
`@resurrect-restore-script-path`, so it works with either manager and custom plugin
directories.

Continuum is numbered `99`, after Resurrect at `80`; keep themes before it.
Its fragment sets `@tpm-parallel false` so Ahiru preserves load order. Automatic
saves require an enabled status line and Continuum's status hook to remain intact.

## Install and use

Render the desired manager and both plugin playbooks with the local connector:

```sh
ansible-playbook -i 'localhost,' -c local tpm-ahiru.src.pb
ansible-playbook -i 'localhost,' -c local tmux-resurrect.etc.pb tmux-continuum.etc.pb
```

Use each playbook's rendered `DIR` below; these are the ordinary system-layout
paths. USERMODE or prefix overrides can select different material locations.

```sh
host=/usr/local/src/tpm-ahiru
"$host/bin/install-user.sh"
/etc/opt/tmux-resurrect/bin/install-tmux.sh "$host"
/etc/opt/tmux-continuum/bin/install-tmux.sh "$host"

# Inside tmux, source the root chosen by install-user.sh:
tmux source-file ~/.tmux.conf
# Use ~/.config/tmux/tmux.conf instead if that is your root (honoring XDG_CONFIG_HOME).
ahiru-tpm install

# Restore only when wanted, from inside a tmux session:
/etc/opt/tmux-resurrect/bin/restore-session.sh
```

For TPM, select its deployment as `host`, then use **prefix + I** after sourcing
the root to install plugins. `install-tmux.sh` registers configuration; plugin
downloads remain with the selected manager.

Administrative examples:

```sh
"$host/bin/config-remote.mjs" list
"$host/bin/config-remote.mjs" disable tmux/plugins 99-continuum.conf
"$host/bin/config-remote.mjs" enable tmux/plugins 99-continuum.conf
"$host/bin/config-status.sh" --definition tmux
```

Reinstalling a contributed fragment preserves its disabled state. Source the root
to apply configuration changes to a running server; stopping an already-loaded
Continuum saver can be done explicitly with `tmux set -g @continuum-save-interval 0`.

## Existing Ahiru installations

The plugin list's old managed block is replaced by the CONFIG source block.
Older installations can also contain a separate `<NAME>-resurrect` settings block
and already-installed Ctrl-s/Ctrl-r bindings. Retire the old settings block after
registering the separate plugins (adjust root and NAME for your installation):

```sh
block-in-file --remove tpm-ahiru-resurrect -o ~/.tmux.conf
```

The new playbooks do not own arbitrary live keybindings. Remove those historical
bindings explicitly if still present:

```sh
tmux unbind-key C-s
tmux unbind-key C-r
```

The old generated Ahiru `bin/restore-session.sh` may remain on disk after a render;
the maintained helper now belongs to the Resurrect deployment.

## Verification

[`tests/integration/tmux_plugins.test.py`](/tests/integration/tmux_plugins.test.py)
renders real CONFIG runtimes in isolation and exercises both receivers, reverse
delivery order, root preservation, linked publication, disabled-state retention,
coexistence with another CONFIG using the same local input name, and the manual
restore session guard. An isolated upstream initialization probe also confirmed
that the whitespace binding options preserve existing keys and the helper can
invoke a published restore path containing spaces and an apostrophe.
