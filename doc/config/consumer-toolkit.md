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

Each file is a real symlink through `bin/config/command.mjs` to the shared built
dispatcher at `bin/compfuzor-runtime.mjs`. Declarative argument parsing, alias
inference, and action-specific help remain in domain-grouped TypeScript sources;
the dispatcher selects an action and context, then delegates to the bundled
assembly, input, publication, install, and status operations. The transaction
runner and shell processor leaves remain internal. There is no public
`config.sh`, `config-context.sh`, per-recipe assembly wrapper, per-context
wrapper, or strategy-specific wrapper.

## Controller compilation and deployed runtime

The Python filter and lookup plugins are Ansible controller code. They compile
declarations while a playbook renders and are not copied to managed machines.
The managed CONFIG, Zim, LINKS, and config-remote runtime is one JavaScript
multicall artifact built by
[Vite+](https://viteplus.dev/guide/pack/) from the TypeScript sources:

```text
files/                         # source checkout only
  config/*.ts
  links/*.ts
  zim/*.ts
  config-remote.ts             # source CLI wrapper
  config-remote/*.ts
  runtime/*.ts                 # minimal root dispatch only
runtime/                       # checked-in `pnpm build` product + vendored controller
  compfuzor-runtime.mjs
  zimfw.zsh                    # vendored zimfw release; GET_URLS refreshes deployments
<deployment>/bin/              # one copied product and stable aliases
  compfuzor-runtime.mjs
  config/command.mjs -> ../compfuzor-runtime.mjs
  config-remote.mjs  -> compfuzor-runtime.mjs
  links/links.mjs    -> ../compfuzor-runtime.mjs
  links.mjs          -> compfuzor-runtime.mjs
  zim/install.mjs    -> ../compfuzor-runtime.mjs
```

Run `pnpm install` once after checkout changes, then `pnpm build` to regenerate
the self-contained executable. Its shebang and executable mode are preserved.
The generated artifact is committed because the controller needs it while
rendering arbitrary playbooks; target playbooks never run pnpm or perform
network installation. Rendering fails with a `pnpm build` instruction if the
artifact is absent.

Each participating subsystem contributes the same compatible artifact claim and
only its own aliases. The existing name-keyed BINS merge deduplicates those
claims, so standalone CONFIG or LINKS deployments remain complete while a Zim
host still installs only one regular `.mjs` file. The root dispatcher follows
the lexical symlink chain before realpath erases it; CONFIG therefore retains
its fixed, chained, and explicit custom-alias behavior.

No `.py` or `.ts` file is part of the relevant deployed `bin` tree. Other raw
TypeScript deployment surfaces remain deliberately outside this cutover:
kernel status reporters (`status-modules.ts`, `status-cmdline.ts`, and
`status-sysctl.ts`) and the Repart runtime (also embedded into Mkosi images).
The former MCP drop-in adapter pair was deleted; existing deployments may
retain old copies until deliberate cleanup. OpenCode's `backup.ts` uses the
separate Node bin template. These domains are not imports or dependencies of
the CONFIG/Zim/LINKS bundles.

### Read-only runtime catalog

Every rendered deployment receives attributed catalog data under
`etc/compfuzor-runtime/`. Deployments that already carry the omnibus runtime
also receive `compfuzor-catalog.sh`; ordinary deployments are not forced to add
a Node runtime merely for catalog emission.

```text
etc/compfuzor-runtime/catalog.json
etc/compfuzor-runtime/workflows/compiled/NN-FLOW-SLUG.json
etc/compfuzor-runtime/workflows/site/
```

The initial catalog projects existing BINS and STATUSES behavior for inspection
only. It records `execution.authority: legacy-shell` and never invokes a
catalogued handler. The compiled catalog is a closed membership index, so stale
unpruned files are not treated as current declarations. A site file may move a
declared contribution lexically or tombstone it; changed behavior requires a
future explicitly attributed native contribution.

```bash
compfuzor-catalog.sh contributors
compfuzor-catalog.sh actions
compfuzor-catalog.sh flows
compfuzor-catalog.sh flow install
compfuzor-runtime.mjs catalog --deployment /opt/example flow status
```

### Experimental catalog flow execution

`RUNTIME_FLOW_EXECUTION: true` changes only the opted-in deployment: its catalog
records `authority: catalog`, the runtime emits `compfuzor-flow.sh`, and
build/install/status may execute their validated indexed invocations
sequentially. Omission retains the read-only default.

```bash
compfuzor-flow.sh --dry-run install
compfuzor-flow.sh build
compfuzor-flow.sh status
```

The executor accepts no broadcast child arguments. Fixed arguments come from
each descriptor. Build/install stop at the first failed mutation; status runs
all reporters and folds legacy 0/1/2 semantics. Executable handlers must resolve
beneath the deployment root, including through symlinks. Child processes receive
the selected deployment as `DIR`; ambient foreign deployment state is not
inherited. SIGINT/SIGTERM are forwarded to the detached child process group and
the runner waits for termination. Site placement and tombstones are applied
through the same closed catalog selection used by inspection.

Legacy shell roots with authored bodies remain opaque invocations so their body
and generated children execute exactly once. Pure generated roots may be
represented by their ordered immediate children. This is migration behavior;
native plural composition remains the destination.

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
publication, input put/remove, and ordinary install reject `canonical` rather
than pretending those relationships are meaningful. Input list/status and the
explicit enable/disable administration of mutable canonical fragments remain
available. Canonical assembly still runs during playbook generation before
consumer installation.

## Actions and recipe selection

Each fixed command's `--help` describes only that action. In particular,
`config-assemble.sh --help` points to its existing `--list` operation for recipe
discovery; operators do not need to read the internal spec. Both `--flag value`
and `--flag=value` are accepted, and unknown options fail under strict Node
argument parsing.

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

# Assemble/check one or several recipes; stdout is byte-exactly one recipe.
config-assemble.sh zimrc zimenv
config-assemble.sh --check zimrc
config-assemble.sh --stdout zimrc
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

`--stdout` is the one recipe-selection exception: resolution must produce
exactly one recipe. Zero names is accepted only for a context with exactly one
`apply: true` recipe; zero names selecting several, or several explicit names,
fails with exit 2 before any processor runs. This preserves a byte-exact stream
without inventing a framing format or leaking an earlier candidate before a
later validation failure.

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

## Portable JSON inputs

`json-deep-merge` inputs can opt into placement and environment substitution.
Other inputs keep the ordinary deep-merge behavior. A glob with `place` can
wrap raw JSON records as it assembles, without changing the producer file or
creating a client-specific adapter:

```yaml
CONFIGS:
  opencode.json:
    processor: json-deep-merge
    inputs:
      - file: base.json
      - glob: mcp/*.json                 # existing pre-wrapped fragments
        name: mcp
      - glob: mcp-portable/*.json
        name: mcp-portable
        remote: true
        place:
          at: mcp.servers               # dotted object path
          as: object                    # object | array; explicit, not inferred
          command_args: true            # optional: split a command array
          rename:                       # optional: rename record keys
            environment: env
        envsubst:
          file: ../env.export           # relative to each real producer file
```

```sh
bin/config-remote.mjs put mcp-portable \
  /usr/local/src/example-mcp/etc/mcp.json example.json
```

The remote command still manages **only links** and rebuilds the canonical
config transactionally. With `as: object`, each input must be a JSON object;
`example.json` places it at `mcp.servers.example`. With `as: array`, each
input must be an array, and its elements are appended at `at` in sorted file
order; the filename does not become a key. A pre-existing destination with the
wrong type fails assembly. A named slot replaces its entire previous record,
so a former local server's `command` cannot leak into a remote server with the
same name. Use separate globs for pre-wrapped and
portable records to avoid wrapping an already-wrapped record again.

Two optional record adaptations run before object placement, in order:

- `command_args: true` splits an array-valued `command` into `command` (the
  first element, a string) plus `args` (the rest, appended after any existing
  `args`) — the convention most MCP clients use (Claude, Cursor, amp, mcp-cli).
  A `command` that is already a string passes through; an empty array fails
  assembly. Records without `command` (for example remote servers) are
  untouched.
- `rename` maps top-level record keys to the client's vocabulary, for example
  `environment: env` for mcp-cli, whose loader reads `env` and ignores
  `environment`. Unlisted keys are left alone.

Neither adaptation is inferred: a client declares the record shape it wants,
and a mismatch fails loudly instead of guessing.

`envsubst.file` opts into **single-pass**, JSON-aware `${NAME}` substitution
in string values only. The file is sourced as shell code in a per-input
subprocess; **only configure trusted producer `env.export` files**. Relative
paths are resolved from the symlink's real target directory, not the consumer's
directory. Values from the env file override inherited environment variables;
an undefined name fails assembly (including during remote `put`, which rolls
the link back). Literal `{env:NAME}` is left for the consumer application to
resolve at runtime. This is preferable for credentials: `${NAME}` materializes
its value into the assembled config. Check/status may show config diffs, so
use quiet check when avoiding secret values in terminal output.

There is no automatic registration or producer install hook: select a server
name explicitly with `put ... name.json`; `config-remote.mjs` keeps disabled
links disabled on subsequent puts. Remove or disable a link deliberately when
no longer needed. Changing a producer record or env file changes assembly
results, but the consumer must reassemble and restart/reload its application
when appropriate.

The OpenCode and `mcp-cli` playbooks opt into portable input placement.
OpenCode consumes records as-is (`mcp.servers`, command arrays);
`mcp-cli` declares `command_args: true` plus `rename: {environment: env}` for
its `command`/`args`/`env` schema and relies on its own runtime `${VAR}`
substitution instead of `envsubst`, keeping secrets out of the assembled file.
Amp still accepts only its already-wrapped `mcp/*.json` fragments; it can
adopt the same declaration when its schema is wanted. Do not link a raw
producer record into a glob that has not declared `place`. This interface does
not silently infer client-specific field mappings.

## Manual aliases

Compfuzor generates no context aliases or alias map. An operator may create a
context/action alias in the deterministic order `config-CONTEXT-ACTION.sh`:

```bash
ln -s config-assemble.sh config-user-assemble.sh
ln -s config/command.mjs config-host-status.sh
```

The alias may point through a fixed action symlink or directly to the internal
dispatcher. The unresolved invoked basename supplies one known action and one
declared context. It never selects copy/link strategy. Unknown or ambiguous
names fail. Each explicit flag bypasses the corresponding stale alias piece;
explicit `--action` and `--context` together bypass alias parsing completely.

Fixed generated names infer only action. Direct internal invocation must name
the action:

```bash
bin/config/command.mjs \
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

The standalone transaction runner uses `set -euo pipefail`. Candidate creation,
staging copy/mode changes, and output moves fail closed. Every selected
candidate is built and validated before staging; staging failures mutate no
outputs, and a later commit move failure rolls back outputs already moved in
the same transaction. Temporary candidates and backups are cleaned on failure.
Only expected comparison/diff/reporting outcomes are explicitly tolerated.

### Runtime bypass

`COMPFUZOR_CONFIG_BYPASS=1` and
`COMPFUZOR_CONFIG_CONTEXTS_BYPASS=1` apply only to the ordinary typed CONFIG
install operation. `config-install.sh` returns success with a skip report and
does not resolve strategy settings, synchronize inputs, publish, assemble, or
mutate output. Internal runner/processors are bypass-neutral, preventing a
guarded processor from returning success without producing a candidate.

Explicit operator/diagnostic actions remain active under CONFIG bypass:
`config-assemble.sh`, `config-status.sh`, `config-sync-inputs.sh`,
`config-publish.sh`, and `config-inputs.sh` keep their normal contracts. This is
intentional: bypass suppresses ordinary composed installation, not observation
or an explicitly requested repair/admin operation.

Status reports input inventory, assembly readiness, and output health. Matching
copies, equivalent links, and matching local assemblies are healthy. Direct
`config-status.sh` exits 0 clean, 1 drift, or 2 evaluation error. Its structured
aggregate reporter metadata marks exit 2 as an error; aggregate `status.sh`
continues to return its boolean attention result without treating CONFIG errors
as historical “not applicable.” The human table calls its two identity columns
`recipe` and `item`: they intentionally coincide for whole outputs and differ
for named fragments.

Structured status records may also bind fixed arguments without creating a
wrapper. On a Zim host, aggregate status runs generic `config-status.sh` once,
then invokes `status-zim.sh --activation-only`; direct `status-zim.sh` remains
complete. String reporter records retain their historical exit-2
not-applicable behavior and receive caller arguments unchanged.

## Zim complete installation

`ZIM_CONTEXTS` remains a small domain adapter over CONFIG bindings. It adds
loader, cache, registry, and producer-import paths; those are not CONFIG
concepts. The host surface remains:

```text
install-zim.sh [--context NAME] [--install assemble|copy|link] [--dropins copy|link]
status-zim.sh [--context NAME] [--activation-only]
install-zim-context.sh [--context NAME] PRODUCER_DIR
install-zim-donor.sh PRODUCER_DIR
```

`install-zim.sh` uses the shared selected-name resolver and typed CONFIG install
operation, then installs both projected loaders, builds both caches, and applies
the registry. `status-zim.sh` includes selected-context generic CONFIG health as
well as loaders, caches, and registry, preserving direct 0/1/2 distinction.
Clean and drifting loader/cache checks each name their channel, component, and
path, so a clean run confirms all four activation artifacts instead of printing
only failures.
Install and status resolve context from explicit flag, supported Zim alias,
`COMPFUZOR_ZIM_CONTEXT`, generic `COMPFUZOR_CONTEXT`, then compiled
`defaultContext`. Install/drop-in settings are not resolved during status.

When CONFIG install is bypassed inside a Zim install, the typed skip outcome is
not mistaken for completed config work. If both selected `zimenv` and `zimrc`
outputs already resolve to regular files, Zim may continue its independent
loader/cache/registry work from those existing outputs. If either is absent,
the remaining Zim install is skipped successfully with a reason. No empty or
missing config is passed to cache construction.

`COMPFUZOR_ZIM_BYPASS=1` skips ordinary Zim `install` and producer `import`
before context or strategy resolution, for both direct and composed calls.
Status remains active and observable. Generation-time `ZIM_BYPASS` behavior is
unchanged; no additional per-step Zim bypass vocabulary is introduced.

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
- [`command0-review0.solx.md`](/design/config-context/command0-review0.solx.md)
  records the strict-runner, bypass, aggregate-status, and stdout corrections
  found during independent review.
- [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
  compiles config spec v2, canonical/default contexts, modules, and fixed links.
- [`config/cli.ts`](/files/config/cli.ts) owns strict argument parsing, fixed
  help, and alias inference; [`config/command.ts`](/files/config/command.ts)
  selects typed operations and dispatches them.
- [`config/invocation.ts`](/files/config/invocation.ts) is the small shared
  selected-name resolver used by CONFIG and Zim.
- [`config/assembly.ts`](/files/config/assembly.ts),
  [`config/input-state.ts`](/files/config/input-state.ts),
  [`config/inputs.ts`](/files/config/inputs.ts),
  [`config/publication.ts`](/files/config/publication.ts), and
  [`config/status.ts`](/files/config/status.ts) separate assembly, input
  observation, input mutation, publication, and whole-context status.
- [`config/file-state.ts`](/files/config/file-state.ts) contains the common
  regular-file availability and byte-comparison observations used by input and
  output status.
- [`config-run.sh`](/files/config-run.sh) remains the single build, validation,
  atomic commit, and rollback transaction runner.
- [`zim/cli.ts`](/files/zim/cli.ts),
  [`zim/activation.ts`](/files/zim/activation.ts), and
  [`zim/install.ts`](/files/zim/install.ts) separate selected invocation,
  loader/cache mechanics, and complete-install/import/status orchestration.
- [`links/delivery.ts`](/files/links/delivery.ts) remains the shared atomic
  copy/link primitive.
- [`log.md`](/doc/config/log.md) records maintained live-render commands,
  verification outcomes, physical representations, and unpruned migration
  residue.
