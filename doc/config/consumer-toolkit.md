# Consumer configuration toolkit

Compfuzor can compile one `CONFIGS` recipe once and bind it to explicit user or
system consumer roots at runtime. The canonical deployment stays reusable;
consumer input choices and assembled outputs stay independent.

## What runs automatically

Zim joins ordinary install composition through one complete installer. With the
current default context (`user`), the generated shape is:

```text
install-user.sh                    (ordinary user install — one command)
└─ install-zim.sh                  complete selected-context setup
   ├─ config seed/assembly or whole copy/link
   ├─ .zshenv and .zshrc loader blocks
   ├─ zimenv and zimrc caches
   └─ canonical host registry link
```

`install-zim.sh` invokes the generic config toolkit exactly once, then installs
both loaders, builds both caches, and applies the registry exactly once. Zim's
owned config contexts declare `compose: false`, so their directly invokable
`install-config-<context>.sh` tools cannot duplicate that work through the
package compositor. If Zim's compiled default is a system context, the same
base `install-zim.sh` joins bare `install.sh` instead of `install-user.sh`.
Neither path escalates privileges.

`install-config-user.sh` remains the config domain's ordinary dispatcher; its
action comes from the declared `install:` default or
`COMPFUZOR_CONFIG_INSTALL_STRATEGY`.
The other generated commands never run automatically — `config-user.sh`
(assembly/preview), the drop-in refresh and whole-output commands, and the
input tools. `status-config-context-user.sh` also runs through the aggregate
`status.sh` reporter list.

## Declare a context

The smallest useful declaration binds where a consumer's files live:

```yaml
CONFIG_CONTEXTS:
  user:
    scope: user        # user | system — composition lane + default root classes
    root: config       # ${XDG_CONFIG_HOME:-$HOME/.config} for the invoking user
    subpath: zsh       # optional path below the root
    configs: [zimrc, zimenv]   # which compiled configs to expose (omit = all)
```

System contexts use the same assembly implementation but run with the caller's
existing authority; the config tools never invoke sudo.

Two optional keys choose runtime-overridable defaults for the ordinary
dispatcher; a third assigns composition ownership:

```yaml
    install: assemble   # assemble | copy | link — what install-config-user.sh does
    dropins: link       # link | copy — how donor fragments are seeded/refreshed
    compose: false      # optional; keep the ordinary installer manually invoked
```

Paths under canonical `ETC` keep their relative layout beneath the context
root (`zimrc.d/` → `~/.config/zsh/zimrc.d/`). Inputs or outputs outside `ETC`,
or runtime-selected destinations, need explicit per-config bindings:

```yaml
    configs:
      app:
        output: {env: APP_CONFIG_FILE, default: app.conf}
        inputs:
          0: inputs/base.conf        # by input index
          fragments: local/app.d     # by glob input name
```

Declaration options bind paths or pick defaults — they never add or remove
generated files. Every context gets the same command set; the strategy-variant
scripts differ only in baked arguments over one shared runtime.
`CONFIG_CONTEXTS_BYPASS=True` suppresses the whole toolkit at generation;
`COMPFUZOR_CONFIG_CONTEXTS_BYPASS=1` skips the composed dispatcher at runtime.

### Runtime strategy selection

Copy versus link does not require picking a different file:

```bash
COMPFUZOR_CONFIG_INSTALL_STRATEGY=link install-config-user.sh        # whole-link run
COMPFUZOR_CONFIG_DROPINS_STRATEGY=copy install-config-user-dropins.sh  # copy refresh
```

Export either in your shell for a recurring preference; the playbook default
stays authoritative for fresh users. The per-strategy commands
(`install-config-user-copy.sh`, `-link.sh`, …) are stable, discoverable stems
for the same actions — conveniences, not separate configurations.

## Generated commands

Each command below is a one-line wrapper over the shared `config/toolkit.ts`
runtime (or `config-context.ts` for assembly); the strategy variants differ
only in baked arguments. For a context named `user`:

```text
config-user.sh [--list | --check | --stdout] [CONFIG]
install-config-user.sh [CONFIG]
install-config-user-dropins.sh [CONFIG]
install-config-user-dropins-{copy,link}.sh [CONFIG]
install-config-user-{copy,link}.sh [CONFIG]
config-inputs-user.sh list|status|put|enable|disable|remove ...
status-config-context-user.sh [CONFIG] [--json | --json-array]
```

That is nine context wrappers: one assembly command, one ordinary installer,
three drop-in installers, two whole-output installers, one input operator, and
one status reporter. Zim does not remove them; it only keeps the ordinary
installer out of package composition for a Zim-owned context.

By default only `install-config-user.sh` joins ordinary install composition.
`compose: false` keeps even that ordinary dispatcher manual; explicit strategy
commands never run automatically.

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

A linked fragment exposes the donor's live bytes: editing through that link
edits the donor if your filesystem permissions allow it. For independent content
edits, make the fragment a copy first (using `put --strategy copy`, or the
drop-in copy command for the selected config), or add a new local fragment.
Renaming/enabling/disabling the local link changes only the local directory
entry. Reassembly does not refresh those entries from the donor.

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

If a bound consumer input directory or output entry physically aliases its
canonical donor location through a parent-directory symlink, status reports an
`alias-hazard` and mutating consumer commands refuse it. Final per-file links to
donor files remain normal, replaceable consumer entries.

## Zim activation contexts

`CONFIG_CONTEXTS` owns config input and output bindings. `ZIM_CONTEXTS` is a
small activation layer that references one of those bindings and adds the
loader, cache, and registry destinations needed for a complete Zim install.
The referenced config context must set `compose: false`; compilation rejects a
Zim-owned context that could also compose its generic installer. The checked-in
host declaration is intentionally concise:

```yaml
ZIM_CONTEXT: user
ZIM_CONTEXTS:
  user:
    config: user
```

A user-scoped config context gets runtime-aware activation defaults:

| Setting | Environment override | Default |
|---|---|---|
| loader root | `ZDOTDIR` | `${HOME}` |
| zimrc cache home | `ZIM_HOME` | `${HOME}/.cache/zim` |
| zimenv cache home | `ZIM_ENV_HOME` | `${HOME}/.cache/zim-env` |
| registry destination | `ZIM_CONFIG_LINK` | `${XDG_CONFIG_HOME}/zsh/zimfw.conf` |

A system-scoped context must declare all four explicitly. It never silently
inherits `HOME`, XDG, or the user cache defaults:

```yaml
CONFIG_CONTEXTS:
  host:
    scope: system
    root: /srv/shell/config
    configs: [zimrc, zimenv]
    compose: false

ZIM_CONTEXTS:
  host:
    config: host
    loader_root: /srv/shell/startup
    zimrc_home: /srv/shell/cache/zim
    zimenv_home: /srv/shell/cache/zim-env
    registry: /srv/shell/registry/zimfw.conf
```

The caller must already have authority to write those paths. Context selection
never implies `sudo`.

The generated `zim.spec.json` is version 2. Alongside activation contexts, its
canonical section explicitly names `zimrcLegacy`, `zimenvLegacy`,
`zimrcLoaderTemplate`, `zimenvLoaderTemplate`, and `emergencyModule`. These are
runtime inputs rather than inferred sibling paths. A v1 deployment fails with
clear rerender guidance instead of reinterpreting old fields.

### One installer and user-managed context aliases

The ordinary interface is:

```text
install-zim.sh --context NAME [--install assemble|copy|link] [--dropins copy|link]
status-zim.sh [--context NAME]
```

Each setting resolves independently in this order:

1. an explicit CLI flag;
2. the invoked basename, for context only;
3. runtime environment;
4. the compiled default.

`COMPFUZOR_ZIM_CONTEXT` selects a runtime context. Install and drop-in strategy
selection accepts `COMPFUZOR_ZIM_INSTALL_STRATEGY` and
`COMPFUZOR_ZIM_DROPINS_STRATEGY`; the existing
`COMPFUZOR_CONFIG_INSTALL_STRATEGY` and
`COMPFUZOR_CONFIG_DROPINS_STRATEGY` names remain compatible fallbacks.

Compfuzor generates **no command aliases or alias map**. An operator may create
a symlink manually using the deterministic `install-zim-<declared-context>.sh`
naming convention:

```bash
cd /opt/zim-main/bin
ln -s install-zim.sh install-zim-host.sh
./install-zim-host.sh                 # infers --context host
./install-zim-host.sh --context user  # explicit CLI wins
```

The wrapper captures its basename before resolving the symlink. An undeclared
context or any other non-base basename fails with guidance instead of silently
using the default. Strategy aliases and Cartesian alias filenames are not
supported; use flags or environment variables. Context names `donor` and
`context` are reserved for the canonical admin and consumer-import commands.

### Exact generated surface

For a Zim host, activation compilation adds exactly:

```text
etc/zim.spec.json
bin/install-zim.sh
bin/status-zim.sh
bin/zim/install.ts
```

The host also retains the two explicit noncomposed role commands:

```text
bin/install-zim-donor.sh    # canonical donor administration
bin/install-zim-context.sh  # consumer-context producer import
```

The stable LINKS manager modules used by the registry are shared generated
infrastructure, not Zim installer variants. There is no generated
`install-zim-user.sh`, `install-zim-<context>.sh`, loader/cache/registry leaf,
or alias symlink.

`etc/zimenv.zsh` and `etc/zimrc.zsh` are the two specialized canonical loader
templates. The shared Zim runtime projects safely quoted selected-context
config/cache defaults into their placeholders, then sends those projected bytes
to `block-in-file`. Status creates its expected bytes with the same projector.
A declared system loader therefore works with all `ZIM_*` selectors unset while
remaining overrideable through `ZIM_ENV_HOME`, `ZIM_HOME`, `ZIM_ENV_CONFIG`, and
`ZIM_CONFIG_FILE`. `zimenv` retains its anonymous no-leak scope; `zimrc` retains
its ordinary global assignments and emergency behavior.

## Zim daily workflow

The checked-in Zim host exposes `zimrc` and `zimenv` through the default user
context. Its own baseline roster is canonical; the ordinary workflow links
those donor fragments into the user's XDG config tree and assembles there.

These commands exist only after rerendering the updated playbook. This change
has not been deployed to a live `/opt/zim-main`. The invoking user must be able
to read the canonical donor files; the toolkit does not broaden donor
permissions or invoke sudo.

```bash
# Complete initial setup: seed/assemble, install both loaders, build both
# caches, and install the canonical registry link.
/opt/zim-main/bin/install-user.sh

# Re-run the same complete operation directly, or select another declaration.
/opt/zim-main/bin/install-zim.sh --context user
/opt/zim-main/bin/status-zim.sh --context user

# Daily config-only operation: seed absent baseline inputs and assemble.
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
producer into the shared canonical donor and is never part of ordinary install.
Contributor `install-zimfw.sh [--context NAME]` instead calls
`install-zim-context.sh` to import that producer into the selected consumer
context, assemble each touched channel once, and build each touched cache once.
Its filename is scope-neutral; explicit `scope: [user]` metadata composes it into
the producer package's `install-user.sh`. Other compositor arguments are ignored.

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

node files/zim/install.ts install \
  --spec /path/to/deployment/etc/zim.spec.json \
  --config-spec /path/to/deployment/etc/config.spec.json \
  --config-runner /path/to/deployment/bin/config.sh --context user

node files/links/links.ts status /path/to/deployment/links.json
```

Generated deployment scripts remain the normal operator interface; these source
commands are for development and diagnosis.

## Implementation references

- [`build5.solx.md`](/.design/config-user-target/build5.solx.md) records the
  implementation checkpoint, focused verification, and retained scratch proof.
- [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
  compiles bindings and commands.
- [`zim_context_compile.py`](/library/filter_plugins/zim_context_compile.py)
  validates activation declarations and emits the one Zim runtime surface.
- [`config/context.ts`](/files/config/context.ts) resolves consumer selectors.
- [`config/toolkit.ts`](/files/config/toolkit.ts) owns seed, refresh, input
  mutation, whole-output delivery, and status.
- [`zim/install.ts`](/files/zim/install.ts) coordinates selected-context config,
  loaders, caches, registry, imports, and status.
- [`links/delivery.ts`](/files/links/delivery.ts) is the shared atomic copy/link
  primitive.
- [`config-run.sh`](/files/config-run.sh) remains the single processor,
  validation, and commit runtime.
