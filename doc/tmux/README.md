---
type: Reference
title: Tmux plugin receivers and optional persistence
description: Ahiru and TPM CONFIG contribution blocks, separate persistence playbooks, and explicit session restoration without keybindings.
resource: /doc/tmux/README.md
status: active
generated: {by: 'model:openai/gpt-6-astra', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed1c3f231ffec43Dwg4C35l77Z
    title: Separate persistence, deploy shared CONFIG receivers, and add verified owner-managed Ahiru activation
  - resource: opencode://ses_ed1bfc279ffeymOQ2ei8Svllmx
    title: Independent integration review and identification of duplicate-declaration upgrade cases
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
Select one plugin manager for a user's tmux configuration: loading both manager
blocks would declare and initialize the same plugins twice.

Fragments in `etc/tmux-plugins.d/*.conf` concatenate in filename order into the
fully generated `etc/tmux-plugins.conf`. Source membership and provenance remain
in CONFIG's input inventory. The manager's `install-user.sh` publishes a link
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

The [verified user deployment](/doc/tmux/deployment.md) records the installed
paths, live checks, and ready-to-run restore command for `rektide`.

Render the desired manager and both plugin playbooks with the local connector:

```sh
ansible-playbook -i 'localhost,' -c local tpm-ahiru.src.pb -e NAME=tpm-ahiru-git
ansible-playbook -i 'localhost,' -c local tmux-resurrect.etc.pb -e USERMODE=True -e NAME=tmux-resurrect-main
ansible-playbook -i 'localhost,' -c local tmux-continuum.etc.pb -e USERMODE=True -e NAME=tmux-continuum-main
```

These examples retain the existing manager material under `/usr/local/src` and
place plugin contributions in the user's config tree. Use each playbook's rendered
`DIR` when selecting other names or prefixes.

```sh
host=/usr/local/src/tpm-ahiru-git
"$host/bin/install-user.sh"
~/.config/tmux-resurrect-main/bin/install-tmux.sh "$host"
~/.config/tmux-continuum-main/bin/install-tmux.sh "$host"

# Apply Ahiru's configuration and plugins to the running tmux server:
"$host/bin/apply-user.sh"

# Restore only when wanted, from inside a tmux session:
~/.config/tmux-resurrect-main/bin/restore-session.sh
```

For TPM, select its deployment as `host`, then use **prefix + I** after sourcing
the root to install plugins. `install-tmux.sh` registers configuration; plugin
downloads remain with the selected manager.

Ahiru's `apply-user.sh` is the complete activation entry point: it checks for a
running tmux server, rebuilds its named CONFIG, ensures user installation, sources
the installed aggregate, installs missing plugins, and runs `ahiru-tpm init`.
Run it after changing or registering fragments; callers need only the deployment
path. `install-user.sh` remains available for configuration installation alone.

Administrative examples:

```sh
"$host/bin/config-remote.mjs" list
"$host/bin/config-remote.mjs" disable tmux/plugins 99-continuum.conf
"$host/bin/config-remote.mjs" enable tmux/plugins 99-continuum.conf
"$host/bin/config-status.sh" --definition tmux
```

Reinstalling a contributed fragment preserves its disabled state. With Ahiru, run
`"$host/bin/apply-user.sh"` to apply configuration changes; stopping an already-loaded
Continuum saver can be done explicitly with `tmux set -g @continuum-save-interval 0`.

## Existing Ahiru installations

When the config root stays the same, the plugin list's old managed block is
replaced by the CONFIG source block.
Older installations can also contain a separate `<NAME>-resurrect` settings block
and already-installed Ctrl-s/Ctrl-r bindings. Retire the old settings block after
registering the separate plugins (adjust root and NAME for your installation):

```sh
block-in-file --remove tpm-ahiru-resurrect -o ~/.tmux.conf
```

An earlier direct-root version of the separate playbooks used `tmux-resurrect`
and `tmux-continuum` blocks containing plugin declarations. If those blocks were
installed, retire them after registering the remote fragments:

```sh
block-in-file --remove tmux-resurrect --remove tmux-continuum -o ~/.tmux.conf
```

Ahiru reads `/etc/tmux.conf`, `~/.tmux.conf`, and the XDG tmux config together,
and rejects duplicate plugin names. If moving the managed configuration from
`~/.tmux.conf` to the XDG root, explicitly retire the superseded manager blocks
from the **old** root after installing the new one:

```sh
block-in-file --remove tpm-ahiru-plugins --remove tpm-ahiru-run \
  --remove tpm-ahiru-resurrect -o ~/.tmux.conf
```

Use the corresponding names when switching from TPM (`tmux-tpm-plugins` and
`tmux-tpm-run`). Inspect all the roots Ahiru reads if it reports “More than one
plugin with the name … has been specified”; keep each plugin declaration in its
selected receiver and remove only the superseded declarations elsewhere.

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
