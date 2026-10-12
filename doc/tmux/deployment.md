---
type: Evidence
title: User Ahiru persistence deployment
description: Live deployment and validation of remote Resurrect and Continuum contributions for rektide, including an isolated restore exercise.
resource: /doc/tmux/deployment.md
status: verified
generated: {by: 'model:openai/gpt-6-astra', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed1c3f231ffec43Dwg4C35l77Z
    title: User deployment, stable assembly correction, save/restore verification, and the deployed Ahiru activation entry point
  - resource: /doc/tmux/README.md
    title: Manager receiver and separate plugin contribution contract
  - resource: /tests/integration/tmux_plugins.test.py
    title: Regression checks for receiver composition, disabled membership, and stable canonical assembly
---

# Deployed user setup — 2026-10-12

User: `rektide`. Existing Ahiru material:
`/usr/local/src/tpm-ahiru-git`, with canonical config under
`/etc/opt/tpm-ahiru-git`. Plugin contribution material was rendered with
`USERMODE=True`:

- `~/.config/tmux-resurrect-main`
- `~/.config/tmux-continuum-main`

Each contributor's `bin/install-tmux.sh` registered its fragment into the host's
`tmux/plugins` remote input. The existing `~/.tmux.conf` plugin block now sources
`~/.config/tmux/compfuzor/tpm-ahiru-git/tmux-plugins.conf`, a link to the canonical
aggregate. The old `tpm-ahiru-git-resurrect` block was retired explicitly.

Render logs and the pre-migration config/keybinding backup are local scratch under
`.test-agent/tmux-deploy/`. Existing Ahiru and plugin binaries were reused;
`ahiru-tpm install --load` completed successfully against the updated declarations.
Only the two old bindings pointing to Resurrect's save/restore scripts were removed.

## Verified behavior

- Live `@continuum-restore`: `off`; save interval: `15` minutes.
- Resurrect save/restore binding options: single spaces; prefix Ctrl-s/Ctrl-r have
  no bindings after loading.
- Pane-content capture: `on`; Ahiru parallel loading: `false`.
- Tmux status is enabled, with exactly one Continuum save hook in `status-right`.
- Published Resurrect save and restore script paths resolve to executable files.
- Canonical CONFIG assembly is ready and its output matches. User CONFIG output
  is a healthy link; user-local assembly is correctly reported as an inactive route.
- Continuum's save path completed with 27 pane records, 27 window records and a
  readable pane-content archive containing 27 files. The existing 27 pane IDs and
  process IDs were preserved throughout activation.
- The deployed restore helper restored a deleted window in a private two-window
  tmux fixture using a private snapshot directory. The live user snapshot was not
  restored during validation.

Observed layout snapshot:
`~/.local/share/tmux/resurrect/tmux_resurrect_20261012T040934.txt`.
The pane archive was refreshed at `2026-10-12T04:10:24-04:00`. Resurrect deduplicates
unchanged layouts, so the `last` layout timestamp can remain older than the latest
successful pane-content save.

Live validation found blank separator accumulation in the fully generated aggregate
when using `block-in-file`. The receiver now uses `concat`, retaining managed blocks
only in the user's root config. Both-host integration tests now check canonical
status and byte-stable repeat assembly; they passed after the correction.

## Restore when wanted

From inside the target tmux server:

```sh
~/.config/tmux-resurrect-main/bin/restore-session.sh
```

## Apply configuration changes

The deployed Ahiru host now owns a complete activation command:

```sh
/usr/local/src/tpm-ahiru-git/bin/apply-user.sh
```

It rebuilds the named CONFIG, ensures user installation, sources its own installed
aggregate into the running tmux server, installs missing plugins, and initializes
Ahiru. This command was exercised on the live user server; canonical CONFIG status
was clean afterward, with automatic restoration still off and persistence keys
still unbound. The integration test also verifies that fresh fragment settings are
loaded before plugin-manager installation/initialization on an isolated server.

Inspect configuration health:

```sh
/usr/local/src/tpm-ahiru-git/bin/config-status.sh --definition tmux --context canonical
/usr/local/src/tpm-ahiru-git/bin/config-status.sh --definition tmux --context user
```

See the [tmux guide](/doc/tmux/README.md) for membership changes and migration rules.
