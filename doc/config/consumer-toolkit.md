# Consumer configuration toolkit

Compfuzor exposes CONFIG through six fixed action commands. Context, recipe,
and copy/link choices are runtime selections; they are not multiplied into
generated filenames.

```text
config-install.sh
config-assemble.sh
config-sync-inputs.sh
config-publish.sh
config-inputs.sh
config-status.sh
```

Each file is a real symlink to the one thin dispatcher at
`bin/config/command.ts`. The dispatcher selects an action and context, then
delegates to separate typed assembly, input, publication, install, and status
operations under `bin/config/`. The transaction runner and processor leaves
remain internal. There is no public `config.sh`, `config-context.sh`, per-recipe
assembly wrapper, per-context wrapper, or strategy-specific wrapper.

## Defaults and composition

The Compfuzor-wide default is declared in [`vars/common.yaml`](/vars/common.yaml):

```yaml
CONTEXT_DEFAULT: user
CONFIG_CONTEXT: "{{ CONTEXT_DEFAULT }}"
ZIM_CONTEXT: "{{ CONTEXT_DEFAULT }}"
CONFIG_INSTALL_OWNER: config
```

Precedence at render time is:

1. a domain override such as `CONFIG_CONTEXT` or `ZIM_CONTEXT`;
2. `CONTEXT_DEFAULT`;
3. the built-in global value `user`.

When consumer contexts are declared, the compiler records config spec version
2 and exactly one `defaultContext`; generation fails unless it names a declared
context. At runtime CONFIG context selection is:

1. explicit `--context NAME`;
2. a recognized user-created command alias;
3. `COMPFUZOR_CONFIG_CONTEXT`;
4. generic `COMPFUZOR_CONTEXT`;
5. compiled `defaultContext`.

Only the setting needed by an action is resolved. For example, status does not
validate stale install or input-strategy environment values.

The ordinary config installation joins bare `install.sh` once through explicit
`action: install` BINS metadata on `config-install.sh`; its filename does not
need to begin with `install-`. It is deliberately unscoped because its runtime
default is a context, not a generated user lane. Set `CONFIG_INSTALL_OWNER` to
the complete-install domain when another domain owns the operation. The Zim
host sets it to `zim`, so `install.sh` invokes `install-zim.sh` once and does not
also invoke `config-install.sh`.

## Declare consumer contexts

```yaml
CONFIG_CONTEXTS:
  user:
    scope: user
    root: config
    subpath: zsh
    install: assemble       # assemble | copy | link
    dropins: link           # copy | link input synchronization
    configs: [zimrc, zimenv]

  host:
    scope: system
    root: /srv/shell/config
    install: copy
    dropins: copy
```

`scope` chooses root defaults and describes the binding; it never invokes
`sudo`. User root `config` expands to `${XDG_CONFIG_HOME:-$HOME/.config}`.
System roots are literal. Paths beneath canonical `ETC` retain their relative
layout beneath the selected root. External or environment-selected paths use
per-recipe bindings:

```yaml
    configs:
      app:
        output: {env: APP_CONFIG_FILE, default: app.conf}
        inputs:
          0: inputs/base.conf
          fragments: local/app.d
```

The compiler also records a reserved `canonical` context whose inputs and
outputs are the original CONFIGS paths. It makes donor assembly and status
explicit:

```bash
config-assemble.sh --context canonical
config-status.sh --context canonical
```

Canonical source and destination are intentionally identical. Input sync,
publication, local input mutation, and ordinary install reject `canonical`
rather than pretending those relationships are meaningful. Canonical assembly
still runs during playbook generation before consumer installation.

## Actions and recipe selection

All recipe-level actions accept zero, one, or many positional recipe names:

- zero names selects the context's recipes whose `apply` is not false;
- one or more names selects exactly that subset, including an explicitly named
  `apply: false` recipe;
- duplicate or unknown names fail.

Assembly builds and validates every selected candidate before committing any
output. Multiple selected recipes therefore share the existing CONFIG
transaction and rollback boundary.

```bash
# Seed missing inputs and assemble every apply:true recipe.
config-install.sh

# Install exactly two recipes; explicit strategy beats env and context default.
config-install.sh --context host --strategy assemble --dropins copy zimrc zimenv

# Assemble/check/stream one or several recipes.
config-assemble.sh zimrc zimenv
config-assemble.sh --check zimrc
config-assemble.sh --stdout zimrc zimenv
config-assemble.sh --list

# Refresh existing local input entries. --seed preserves present entries.
config-sync-inputs.sh --strategy copy zimrc zimenv
config-sync-inputs.sh --strategy link --seed

# Publish canonical aggregate outputs as whole copies or links.
config-publish.sh --strategy copy zimrc zimenv
config-publish.sh --strategy link zimrc

# Observe one, several, or all selected recipes.
config-status.sh --json-array zimrc zimenv
```

Install mode resolves as explicit `--strategy` then
`COMPFUZOR_CONFIG_INSTALL_STRATEGY` then the context's `install` value. Install
input strategy resolves as explicit `--dropins` then
`COMPFUZOR_CONFIG_DROPINS_STRATEGY` then context `dropins`. `sync-inputs` and
`inputs put` use `--strategy` with the same input environment/default chain.
Publication requires `--strategy`, or `COMPFUZOR_CONFIG_PUBLISH_STRATEGY`.

Input subactions retain their own selector grammar rather than treating all
positionals as recipe names:

```text
config-inputs.sh list [CONFIG ...]
config-inputs.sh status [CONFIG ...] [--json | --json-array]
config-inputs.sh put CONFIG/INPUT SOURCE [NAME] [--strategy copy|link]
config-inputs.sh enable CONFIG/INPUT NAME
config-inputs.sh disable CONFIG/INPUT NAME
config-inputs.sh remove CONFIG/INPUT [NAME]
```

## Manual aliases

Compfuzor generates no context aliases or alias map. An operator may create a
context/action alias in the deterministic order `config-CONTEXT-ACTION.sh`:

```bash
ln -s config-assemble.sh config-user-assemble.sh
ln -s config/command.ts config-host-status.sh
```

The alias may point through a fixed action symlink or directly to the internal
dispatcher. The unresolved invoked basename supplies one known action and one
declared context. It never selects copy/link strategy. Unknown or ambiguous
names fail. Each explicit flag bypasses the corresponding stale alias piece;
explicit `--action` and `--context` together bypass alias parsing completely.

Fixed generated names infer only action. Direct internal invocation must name
the action:

```bash
node files/config/command.ts \
  --action status --context user \
  --spec /path/to/deployment/etc/config.spec.json \
  --runner /path/to/deployment/bin/config/run.sh zimrc
```

## Safe delivery and status

The permissive Build 4/5 behavior remains intentional:

- seed preserves existing copies, links, edits, disabled names, and extras;
- refresh replaces declared regular-file/symlink entries without a force gate;
- whole publication atomically replaces only regular files or symlinks;
- directories and special files are not replaced;
- no ownership receipt, persistent strategy database, or automatic prune is
  introduced;
- parent-directory physical aliases back into canonical inputs/outputs are
  rejected, while final links to donor files remain normal.

Status reports input inventory, assembly readiness, and output health. Matching
copies, equivalent links, and matching local assemblies are healthy. Direct
`config-status.sh` exits 0 clean, 1 drift, or 2 evaluation error. Its structured
aggregate reporter metadata marks exit 2 as an error; aggregate `status.sh`
continues to return its boolean attention result without treating CONFIG errors
as historical “not applicable.”

## Zim complete installation

`ZIM_CONTEXTS` remains a small domain adapter over CONFIG bindings. It adds
loader, cache, registry, and producer-import paths; those are not CONFIG
concepts. The host surface remains:

```text
install-zim.sh [--context NAME] [--install assemble|copy|link] [--dropins copy|link]
status-zim.sh [--context NAME]
install-zim-context.sh [--context NAME] PRODUCER_DIR
install-zim-donor.sh PRODUCER_DIR
```

`install-zim.sh` uses the shared selected-name resolver and typed CONFIG install
operation, then installs both projected loaders, builds both caches, and applies
the registry. `status-zim.sh` includes selected-context generic CONFIG health as
well as loaders, caches, and registry, preserving direct 0/1/2 distinction.
Install and status resolve context from explicit flag, supported Zim alias,
`COMPFUZOR_ZIM_CONTEXT`, generic `COMPFUZOR_CONTEXT`, then compiled
`defaultContext`. Install/drop-in settings are not resolved during status.

The Zim host composes into bare `install.sh` even when its default context is
`user`; user context does not manufacture `install-user.sh`. Contributor
`install-zimfw.sh` remains explicitly user-scoped and may still compose through
the legacy user lane because that is a contributor-domain choice.

## Old-to-new command mapping

No compatibility aliases are generated.

| Removed command | Current command |
|---|---|
| `config-CONTEXT.sh [CONFIG]` | `config-assemble.sh --context CONTEXT [CONFIG ...]` |
| `install-config-CONTEXT.sh [CONFIG]` | `config-install.sh --context CONTEXT [CONFIG ...]` |
| `install-config-CONTEXT-dropins.sh` | `config-sync-inputs.sh --context CONTEXT` |
| `install-config-CONTEXT-dropins-copy.sh` | `config-sync-inputs.sh --context CONTEXT --strategy copy` |
| `install-config-CONTEXT-dropins-link.sh` | `config-sync-inputs.sh --context CONTEXT --strategy link` |
| `install-config-CONTEXT-copy.sh` | `config-publish.sh --context CONTEXT --strategy copy` |
| `install-config-CONTEXT-link.sh` | `config-publish.sh --context CONTEXT --strategy link` |
| `config-inputs-CONTEXT.sh` | `config-inputs.sh --context CONTEXT` |
| `status-config-context-CONTEXT.sh` | `config-status.sh --context CONTEXT` |
| public `config.sh` | `config-assemble.sh --context canonical` (internal runner: `config/run.sh`) |

Compfuzor does not prune stale files from previously rendered deployments. A
future live migration must remove known old wrappers deliberately.

## Implementation references

- [`command0.solx.md`](/design/config-context/command0.solx.md) records the
  architectural truth tables, implementation boundary, verification evidence,
  and next systemd comparison for this command consolidation.
- [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
  compiles config spec v2, canonical/default contexts, modules, and fixed links.
- [`config/command.ts`](/files/config/command.ts) parses/infer/selects and
  dispatches; [`config/invocation.ts`](/files/config/invocation.ts) is the small
  shared selected-name resolver used by CONFIG and Zim.
- [`config/assembly.ts`](/files/config/assembly.ts),
  [`config/inputs.ts`](/files/config/inputs.ts),
  [`config/publication.ts`](/files/config/publication.ts), and
  [`config/status.ts`](/files/config/status.ts) are typed operation modules.
- [`config-run.sh`](/files/config-run.sh) remains the single build, validation,
  atomic commit, and rollback transaction runner.
- [`zim/install.ts`](/files/zim/install.ts) retains the domain-specific complete
  installation lifecycle.
- [`links/delivery.ts`](/files/links/delivery.ts) remains the shared atomic
  copy/link primitive.
