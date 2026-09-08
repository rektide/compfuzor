# Consumer configuration toolkit

Compfuzor can compile one `CONFIGS` recipe once and bind it to explicit user or
system consumer roots at runtime. The canonical deployment stays reusable;
consumer input choices and assembled outputs stay independent.

## Declare a context

```yaml
CONFIG_CONTEXTS:
  user:
    scope: user
    root: config
    subpath: zsh
    install: assemble # assemble | copy | link
    dropins: link     # link | copy
    configs: [zimrc, zimenv]
```

For user scope, `root: config` means
`${XDG_CONFIG_HOME:-$HOME/.config}` for the invoking user. System contexts use
the same assembly implementation but run with the caller's existing authority;
the config tools never invoke sudo.

Paths under canonical `ETC` keep their relative layout beneath the context
root. External inputs require an explicit binding. Per-config output bindings
may use an environment override:

```yaml
configs:
  app:
    output: {env: APP_CONFIG_FILE, default: app.conf}
```

## Generated commands

For a context named `user`:

```text
config-user.sh [--list | --check | --stdout] [CONFIG]
install-config-user.sh [CONFIG]
install-config-user-dropins-{copy,link}.sh [CONFIG]
install-config-user-{copy,link}.sh [CONFIG]
config-inputs-user.sh list|status|put|enable|disable|remove ...
status-config-context-user.sh [CONFIG] [--json | --json-array]
```

Only `install-config-user.sh` joins ordinary install composition. Explicit
strategy commands never run automatically.

### Operation boundaries

| Operation | Inputs | Output | Existing local choices |
|---|---|---|---|
| default `install` with `assemble` | seeds missing donor entries | assembles locally | preserves links, copies, edits, disabled names, and extras |
| explicit drop-in refresh | refreshes declared donor entries as copy or link | unchanged | preserves enabled/disabled naming; extras remain |
| `config-<context>.sh` | unchanged | assembles locally | consumes current local inputs |
| whole copy/link | unchanged | publishes canonical aggregate | replaces selected regular file or symlink |
| canonical `config-remote.ts` | mutates canonical donor input | rebuilds canonical output | admin operation, not consumer install |

Directories and special files are not replaced. There is no automatic prune,
ownership receipt, force gate, or persistent mode database.

## Status

Context status reports separate rows for:

- **input inventory**: enabled/disabled, copy/link/local, modified, missing, or
  donor-missing;
- **assembly readiness**: whether the shared processor can produce a validated
  candidate from current local inputs;
- **output health**: canonical copy/link, local assembly, missing, or modified.

A matching copy and an equivalent resolved symlink are both healthy. A fresh
whole-copy/link installation is also healthy when local assembly inputs have
never been initialized; its inactive assembly observations remain visible.
`config-user.sh --check` and `config-inputs-user.sh status` remain the strict
questions for the assembly route itself.

## Zim daily workflow

The Zim host exposes `zimrc` and `zimenv` through one user context. Its own
baseline roster is canonical; the default user workflow links those donor
fragments into the user's XDG config tree and assembles there.

```bash
# Seed absent baseline inputs and assemble both local configs.
/opt/zim-main/bin/install-config-user.sh

# Preview local reassembly and inspect all representations.
/opt/zim-main/bin/config-user.sh --check zimrc
/opt/zim-main/bin/status-config-context-user.sh --json-array

# Disable one entry only for this user, then rebuild that channel.
/opt/zim-main/bin/config-inputs-user.sh disable \
  zimrc/zimrc 55-example.conf

# Refresh declared baseline entries while retaining disabled choices.
/opt/zim-main/bin/install-config-user-dropins-link.sh zimrc
# or choose editable independent copies:
/opt/zim-main/bin/install-config-user-dropins-copy.sh zimrc

# Temporarily consume the canonical aggregate, then return to local assembly.
/opt/zim-main/bin/install-config-user-link.sh zimrc
/opt/zim-main/bin/install-config-user-copy.sh zimrc
/opt/zim-main/bin/config-user.sh zimrc
```

`install-zim-donor.sh PRODUCER_DIR` is deliberately different: it promotes a
producer into the shared canonical donor and is never part of user install.
Contributor `install-user-zimfw.sh` instead imports that producer into the
current user's context, assembles each touched channel once, and builds each
touched cache once.

Zim's `.zshenv` and `.zshrc` loaders are independent named blocks. `ZDOTDIR`
selects those startup files; XDG selects the default config tree.
`ZIM_ENV_CONFIG` and `ZIM_CONFIG_FILE` remain explicit output overrides. Values
equal to the old canonical defaults are recognized as migration residue and
normalized to local defaults; a deliberate canonical-following choice uses the
whole-link command above. `ZIM_CONFIG_LINK` is a separate canonical host
registry and never follows the local runtime output.

## Mise

Mise does not declare `CONFIG_CONTEXTS`. Zsh activation benefits through Zim's
`zimenv` channel. Mise's `.bashrc` and `.bash_profile` integrations remain two
independent `block-in-file` installs, with `status-mise-bash.sh` using the shared
named-block reader. The Mise settings action remains separate.

## Running module sources during development

Build output is not used for development. Node 26 runs the TypeScript sources
directly:

```bash
node files/config-context.ts \
  --context user --spec /path/to/deployment/etc/config.spec.json \
  --runner /path/to/deployment/bin/config.sh --check zimrc

node files/config/toolkit.ts \
  --context user --spec /path/to/deployment/etc/config.spec.json \
  --runner /path/to/deployment/bin/config.sh status zimrc --json-array

node files/links/links.ts status /path/to/deployment/links.json
```

Generated deployment scripts remain the normal operator interface; these source
commands are for development and diagnosis.

## Implementation references

- [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
  compiles bindings and commands.
- [`config/context.ts`](/files/config/context.ts) resolves consumer selectors.
- [`config/toolkit.ts`](/files/config/toolkit.ts) owns seed, refresh, input
  mutation, whole-output delivery, and status.
- [`links/delivery.ts`](/files/links/delivery.ts) is the shared atomic copy/link
  primitive.
- [`config-run.sh`](/files/config-run.sh) remains the single processor,
  validation, and commit runtime.
