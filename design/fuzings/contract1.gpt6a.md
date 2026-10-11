---
type: DesignProposal
title: Fuzings as native configuration contributions — ENV, ZIM, and OpenCode
status: draft
generated: {by: 'model:openai/gpt-6-astra', at: 2026-10-11}
sources:
  - resource: urn:opencode:session:ses_ed3f4aaaaffePYlWeomteOWlbg
    title: brave-meadow — reduce descriptor machinery, revisit ENV and ZIM, use etc/env.d/
  - resource: /design/fuzings/contract0.gpt6a.md
    title: Predecessor declaration and action-planning contract
  - resource: /doc/config/consumer-toolkit.md
    title: Existing native input membership, assembly, contexts, and ZIM installation
  - resource: /tasks/compfuzor/fs_env.tasks
    title: Current ENV resolution and rendering
  - resource: /files/_env
    title: Injected deployment variables and assignment order
  - resource: /tasks/compfuzor/gen_zim.tasks
    title: Selected ENV projection and direct ZIM modules
  - resource: /tasks/compfuzor/vars_systemd_env.tasks
    title: SYSTEMD_ENV manager publication, distinct from service EnvironmentFile
  - resource: /opencode.src.pb
    title: Existing OpenCode CONFIG recipe, ENV, and ZIM consumers
  - resource: https://opencode.ai/v2/docs/config
    title: Native OpenCode V2 configuration and application-level discovery
---

# Contract direction

**A fuzing is an explicitly installed contribution to a consumer's native
configuration. The consumer's existing assembly owns how contributions combine.**

The useful minimum is an owned config artifact, a known consumer input, and a
symlink joining them. Local and contributed config use the same input format.
JSON is appropriate where it is the actual configuration or an existing compiled
recipe; membership does not require an additional JSON envelope.

This revises the direction of [contract 0](contract0.gpt6a.md), whose pilot made
fuzings a separate action-selection language with `zim-import`, `shell-source`,
and `exec` kinds. Here **ENV, ZIM, and OpenCode are configuration types**, not
handler kinds. They reuse CONFIG assembly and small native adapters. Lifecycle
operations consume their results.

Human direction includes **`etc/env.d/` as the ENV assembly contribution target**.
This draft interprets that as the input collection; assembled output is a file
such as `env`. The follow-up suggestion is that **`SYSTEMD_ENV` should name
contribution files**. This draft favors that file-selection interface, while
keeping its proposed service use distinct from today's manager-publication
meaning. The other spellings and declaration examples below are proposals.
This document changes the intended contract, not the current implementation.

## Terms

- **Consumer / fuze:** the owner of a selected configuration assembly, including
  its input set, output, validation, and activation policy.
- **Contribution / fuzing:** a producer-owned native input intentionally offered
  to that consumer. The producer can itself be a consumer of the same input.
- **Type:** the native configuration contract: ENV assignments, ZIM declarations,
  OpenCode config fragments, and later other supported formats.
- **Membership:** an installed reference in the consumer's input collection.
- **Exposure:** another route to that same collection or artifact; it does not
  acquire independent membership controls.
- **Assembly / activation:** producing validated config / making its consumer
  use it. A service restart and loading an existing shell are activation work.

## What ENV and ZIM do now

These are source observations as of this draft, not live deployment verification.

### Ordinary ENV is application data mixed with deployment plumbing

[`vars_env.tasks`](/tasks/compfuzor/vars_env.tasks) accepts mapping-or-boolean
`ENV` and `ENV_PRIO`; variable-name lists are separately `ENV_LIST` and
`ENV_PRIO_LIST`. [`fs_env.tasks`](/tasks/compfuzor/fs_env.tasks) resolves the lists,
combines each with its mapping, and renders `env` and `env.export` (plus the
optional usermode variant). Type-specific templates can replace the generic one.

[`files/_env`](/files/_env) unconditionally prepends `DIR`, `NAME`, `TYPE`,
`INSTANCE`, `REPO`, `BUILD_DIR`, and `GLOBAL_BINS_DIR`. It then emits priority
assignments, ordinary assignments, and `COMPFUZOR_ENVS`, an inventory of authored
keys. `env.export` adds `export`; it is not a separately selected application
environment. The inventory is a useful precedent, but it does not make sourcing
the whole file a selective operation.

[`_helpers/env`](/files/_helpers/env) defaults `DIR` only when empty and loads
`$DIR/env.export`, preferring `envdefault` with a direct-source fallback. Thus an
inherited foreign `DIR` can select the wrong deployment's file. Sourcing several
deployment exports in one shell also exposes each deployment's internal names.
The typed action setup already demonstrates a better boundary: it captures and
restores a physically bound action root in
[`actions/environment.sh`](/files/actions/environment.sh).

There is a precedence mismatch to settle: generic `_env` emits `ENV_PRIO` first
and ordinary `ENV` afterward, so a later duplicate assignment wins on direct
sourcing. ZIM instead combines ordinary values and then priority values. Do not
describe these as identical effective environments without correcting or explicitly
accounting for that difference. List handling also differs: ordinary ENV supports
exact-name lookup with uppercase fallback and list-value joining; ZIM's projection
uses uppercase lookup and its own reduction.

### Service environment and SYSTEMD_ENV are different mechanisms

[`vars/systemd.yaml`](/vars/systemd.yaml) ordinarily adds
`EnvironmentFile=-<deployment>/env` when its ENV condition is met. That is how
ordinary ENV reaches a service; today it includes the generic injected variables.
Systemd reads assignment data, not shell expansion. OpenCode additionally has a
later unit-specific credential-pointer environment file, deliberately different
from the stable pointer used by clients.

By contrast, [`vars_systemd_env.tasks`](/tasks/compfuzor/vars_systemd_env.tasks)
turns `SYSTEMD_ENV` into unit start/stop hooks that publish/unset variables in the
systemd manager, and in usermode also the D-Bus activation environment. This is
broader publication, not the compiler for the service's EnvironmentFile. ENV
fuzing must support the service-file path without implicitly publishing to the
manager.

### ZIM already supports explicit env contributions

[`gen_zim.tasks`](/tasks/compfuzor/gen_zim.tasks) makes `ZIM_ENV` a list of keys
projected from ENV/ENV_LIST plus their priority variants. It generates a local
`init.zsh` module and a phase-named ZIM declaration. The generic deployment floor
is not automatically included in that projection.

There is also a direct form, already supported:

```yaml
ZIM_MODULES:
  - name: example-client-env
    phase: 54
    env:
      EXAMPLE_ENDPOINT: "{{ EXAMPLE_ENDPOINT }}"
```

ZIM can independently contribute arrays, aliases, functions, completions, and
source modules. `ZIM_ARRAYS` is intentionally shell-only. `ZIM_ENV` is therefore
a convenience projection, not the only way ZIM can configure itself. One current
integration gap: the outer include condition checks ZIM_MODULE(S)/ZIM_HOST, not
ZIM_ENV or ZIM_ARRAYS alone, although the generator's internal conditions support
them.

[`zim_fragment.py`](/library/filter_plugins/zim_fragment.py) generates env setters
that preserve existing **nonempty** values unless `COMPFUZOR_ENV_OVERWRITE`
selects replacement. Values enter generated double-quoted Zsh expressions, so
this is not yet a general literal-data serializer. Updating the module and
rebuilding caches does not refresh an already-running shell's variables.

Contributors publish channel fragments; the host imports them into CONFIG input
membership. [`zim.opt.pb`](/zim.opt.pb) already assembles `zimrc.d/*.conf` and
`zimenv.d/*.conf` through CONFIG's block-in-file processor. The ZIM adapter then
owns loaders and caches. `ZIM_ENV` (the projection list) and `zimenv` (the ZIM
channel) are different concepts; env modules default to `zimrc` unless selected
otherwise.

### OpenCode already has assembly too

[`opencode.src.pb`](/opencode.src.pb) declares a `json-deep-merge` CONFIG recipe
with base config, `etc_d/*.json`, and native/portable MCP inputs. Portable records
already support placement and explicit producer-env substitution. Its CORS
generator writes a native fragment and calls CONFIG assembly; it does not need a
new JSON merger in a restart script.

OpenCode's own project/global discovery is another, application-owned layer. A
Compfuzor OpenCode type assembles the particular owned config output; it does not
replace that discovery. Server/project configuration and terminal `cli.json`
are separate consumer targets, even when the same deployment manages both.

## Choose native membership plus thin adapters

| Model | Membership and execution authority | Fit here |
|---|---|---|
| Extend BINS/catalog composition | Extended action model owns cross-deployment joins and execution | Useful for future operation composition, but excessive for contributing config bytes. Current flows also have deployment-local execution limits. |
| Separate descriptor/link planner | `fuze.d` descriptors own membership, action kinds, and ordering; another executor must consume its plans | The pilot proves explicit relationships, but repeats facts already expressible by native inputs and recipes. |
| Native input links plus type adapters | Consumer input collection owns membership; CONFIG owns assembly; native adapter owns activation; BINS composes install/operation entrypoints | Selected direction for this draft. Adds the missing ENV processor/projections and OpenCode admission without a second composition language. |

### Membership without envelopes

Prefer the existing native input directory as the maintained membership set.
For ENV, that is **`etc/env.d/`**. If `fuze.d/` is useful as a common view, expose
the very same directories there:

```text
consumer/etc/
  env.d/
    50-local.env
    60-proxy-client.env -> /owned/proxy/etc/env-contributions/client.env
  etc_d/
    proxy.json -> /owned/proxy/etc/opencode-contributions/proxy.json
  fuze.d/
    env -> ../env.d
    opencode -> ../etc_d
```

The ENV reference is reachable as `etc/fuze.d/env/60-proxy-client.env` and as
`etc/env.d/60-proxy-client.env`: **one membership entry, two routes**. ZIM can
similarly expose its existing channel input directories. The producer's directory
names above are illustrative; a producer can supply its own local input directly
when it has exactly the intended contents.

An equally valid placement is a native recipe reading a type collection directly
under `fuze.d/`. There should still be only one collection per input relationship.
A single bundle link such as `fuze.d/proxy -> <producer>/contribution` is another
possible layout, but would require typed bundle expansion into several recipes.
Prefer direct native membership initially; do not silently maintain a second
editable set of links in `env.d/` as a bundle cache.

The consumer recipe/context specifies the accepted format, exact destination,
scope, input order, and output. The link names the exact source. Installation
declarations need source and destination information, but the installed payload
need not repeat deployment ID, target path, fuze ID, scope, and action kind.

Use existing native enable/disable and input mutation operations. A disabled
input is absent from assembly, not a reason to fall back to a different source.
Active missing inputs fail; foreign membership slots are not silently replaced.
An exact matching install preserves existing disable state. Rendering creates
owned artifacts; installation joins the intended consumer. Missing consumer
installation fails with an actionable prerequisite, not a guessed alternate host.
These are intended admission requirements; reuse of CONFIG/LINKS must verify
them rather than assume every existing mutation entrypoint already enforces them.

### How much JSON?

- **No new per-member JSON wrapper** for a native config file plus installed link.
- **No mandatory `fuze.json`** when the consumer already has a CONFIG recipe.
- **No mandatory `fuzings.json` offer index** for explicitly named install sources.
  Retain an index only where a real publication/discovery operation needs one.
- OpenCode fragments remain JSON because they are OpenCode configuration.
- Existing compiled CONFIG/ZIM/LINKS specs remain implementation data. Reusing
  them is different from inventing another parallel specification of membership.
- A deployment contributing to several types may need several native files and
  links. They describe different inputs, not duplicate membership in one input.

## ENV becomes explicit, assemblable configuration

### Separate application values from execution context

`ENV` should define the deployment's **local application contribution**. Resolving
ENV_LIST and priority forms produces that contribution through one shared
normalizer. Explicit producer contributions use the same format. Neither route
automatically injects the deployment floor.

`DIR`, `NAME`, `TYPE`, `INSTANCE`, `REPO`, `BUILD_DIR`, and `GLOBAL_BINS_DIR` belong
to Compfuzor command execution context. Generated bins receive their own bound
context independently of the application environment they consume. A producer's
context must never become a consumer's context by sourcing a fuzing.

An application really needing a generic variable such as `DIR` may declare it
explicitly. The runner must nevertheless keep its own root separately, not treat
that application value as an instruction to change deployment identity. Namespaced
application settings are clearer where possible.

The proposed output relationship is:

```text
explicit local ENV + installed producer env inputs
                         |
                     etc/env.d/
                         |
               consumer file selection
                         |
                  CONFIG ENV assembly
                    /           \
       service assignment file   application shell export/default projection
                    |                         |
        systemd EnvironmentFile        ZIM module / selected launcher

bound Compfuzor execution context -> generated commands only
```

Keep the familiar `env` output for service consumers if useful. `env.export` can
be the application-only shell projection. The exact private runtime-context file
name is an implementation choice; separating the two responsibilities is the
contract. This is a deliberate migration for callers that currently expect the
generic floor in env.export, not a claim that removing it today is harmless.

### SYSTEMD_ENV selects contribution files

Prefer **select files, rather than repeat values or variable names**, for the
systemd consumer interface. Illustrative future declaration, not supported syntax
today:

```yaml
opencodeService:
  SYSTEMD_ENV:
    - 50-origin.env
    - 90-origin-credential.env
```

These names select exact installed contributions under the bound consumer's
`etc/env.d/`. They do not search the machine for similarly named providers. The
service-specific selection is compiled into the existing consumer recipe, with
the explicit list determining input order. A whole-collection recipe instead
uses its declared glob order. Inspection and execution use that compiled
selection; generated wrappers do not maintain another copy of the list.

Explicitly named missing or disabled contributions make that selection incomplete;
selection does not silently enable them. Merely finding another file in env.d
does not add it to a service's explicit selection. For deployments with several
units, bind selection per unit rather than assuming every unit wants the whole
deployment environment.

The example produces a service environment with the credential override last.
A ZIM client projection selects the client contribution file instead, containing
the stable credential pointer. The producer owns each file's values. A contribution
used unchanged by both consumers is the same source file, not two rewritten maps.

There are two execution arrangements to assess at the ENV implementation seam:

- Assemble the selected contributions to a service-specific EnvironmentFile
  through CONFIG; other projections use the same input selection and reducer.
- When contributions already satisfy native systemd EnvironmentFile syntax,
  emit the ordered EnvironmentFile directives directly. Systemd can perform its
  native combination; do not manufacture an aggregate solely for uniformity.
  Inspection and shell projection must still agree on parsing and precedence.

The first fits the proposed shared ENV assembly; the second can be smaller for
a service-only consumer. Neither needs per-contribution descriptor JSON.

**Naming remains a deliberate contract change.** Today's SYSTEMD_ENV is a mapping
for manager publication. If that name becomes service file selection, give the
manager publisher an explicitly named surface and migrate existing declarations.
Alternatively, retain the name for manager publication but change its input to
file selection, with service-file selection separately named. Do not make a
mapping mean manager-wide effects while a list silently means service-local effects.
In either naming arrangement, the manager publisher can consume explicit env
contributions too; publication remains a separately selected operation.

### One resolved map, consumer-specific serialization

The ENV processor reads declared assignment data; it does not source every
producer's executable env.export to discover what changed in `env`. Input order
is the recipe's declared order and native filename order. Proposed precedence:
later contributions replace earlier keys, and priority/local override input is
placed last. Emit each resulting key once. Inspection should explain the winning
source and overridden sources without needing a durable provenance sidecar.

Use a documented assignment-data subset for `.env` contributions, with validated
names and literal values. Settle and test its quoting/escape grammar before
implementation; arbitrary shell scripts are not that subset. No command execution
or implicit ambient-variable expansion occurs while combining inputs. Ansible
interpolation happens before publication; runtime-relative values need an explicit
consumer policy. Existing `$HOME`-dependent shell declarations remain native ZIM
code until an equivalent binding has been specified.

Systemd assignment files and shell exports are separate serializations of the
same selected values. Identical logical configuration need not have identical
quoting bytes. Empty values, quotes, dollar signs, backslashes, Unicode, and
unsupported multiline values must have explicit, tested behavior.

CONFIG already has a custom-processor seam and multi-output validation/commit.
Implement ENV there, rather than adding another assembler. Bare `concat` is
adequate only for a deliberately restricted fixture; it does not resolve duplicate
keys, explain winners, or serialize both consumer formats correctly. The current
built-ins are concat, json-deep-merge, and block-in-file: a native ENV reducer and
serializers are actual missing work.

Assembly must bootstrap from bound command context without requiring its own
not-yet-built application env. `fs_env.tasks` and CONFIG must not both write the
same aggregate after adoption: render local inputs with the former's replacement,
publish aggregate outputs through CONFIG alone.

### Make the contribution boundary explicit

The whole service environment is usually not the desired interactive-shell
environment. Prefer named native env artifacts selected by consumer: origin,
proxy, client, or a genuinely shared contribution. Explicit key projection can
serve migration or a real subset need, but it should not require every consumer
to restate a well-defined contribution key by key. Do not infer an export set by
subtracting a blacklist of Compfuzor variables from a running process's environment.

For OpenCode/proxy, distinguish at least:

| Contribution | Intended consumer |
|---|---|
| Origin listen address/port and server options | Origin service ENV |
| Proxy upstream/listen settings | Proxy service ENV |
| Client endpoint and stable credential-file pointer | Chosen client environment, including its ZIM projection |
| Unit credential-directory pointer override | That exact service, after ordinary ENV |

Shared authored variables may derive these values, but one playbook's Ansible
scope does not supply another's. A common vars input or explicit rendered source
must connect them. Do not independently hand-maintain the same endpoint in ENV,
ZIM, service arguments, and a fuzing descriptor.

## ZIM consumes env; it does not own all env

Keep ZIM's direct `env:` module facility for genuinely shell-owned configuration.
For an application contribution shared with service/launcher consumers, ZIM should
render or load a projection of the selected ENV contribution files. This is the
same file-selection idea as SYSTEMD_ENV, with a Zsh serializer/activation policy.
The existing `ZIM_ENV` key list can remain a migration shorthand for explicit key
selection, backed by the same ENV normalization rather than its current separate
implementation. Decide its file-selector spelling explicitly; do not guess
whether a string names an environment variable or a path.

There are two distinct kinds of reuse:

1. A literal value map is used by several serializers; its authored values have
   one home.
2. Zsh-only arrays, functions, aliases, and expansions remain ZIM-native material.
   They do not become process ENV because ZIM can assemble them.

ZIM's native fragment phase/order stays the shell load-order authority. Fuzings
do not add a second numeric order for the same declarations. A projection's
membership references the selected input set; it does not copy a separately
editable roster into another registry.

For already-running panes, add a narrow activation facility that applies only
the selected client environment and related shell module. It needs an explicit
managed-default policy: refresh values still equal to their previous managed
defaults, preserve deliberate overrides, distinguish unset from intentionally
empty, and define first adoption for shells with no prior state. Removed defaults
need an equally deliberate unset/preserve policy. Keep secret values out of
persistent bookkeeping. This is ZIM/shell activation behavior, not a global
`COMPFUZOR_ENV_OVERWRITE=*` in an OpenCode restart script.

## OpenCode is another native configuration type

Start from its existing CONFIG recipe. Add an explicit contribution/install
surface for OpenCode-native fragments and keep the JSON processor, placement,
validation, and publication in CONFIG. A type adapter binds the intended instance
and config target and supplies native validation where available. JSON validity
alone is not proof of compatibility with the deployed OpenCode version.

The client environment is an ENV contribution used alongside OpenCode config;
it is not arbitrarily inserted into opencode.json. Terminal settings target
cli.json separately. Keep the current native recipe's array/override behavior
explicit rather than assuming a different merger will reproduce it.

An OpenCode operation can then request:

1. Assemble the selected OpenCode and ENV recipes through existing CONFIG.
2. Install/rebuild the selected ZIM projection through the ZIM adapter when needed.
3. Check the intended endpoint and credentials.
4. At the existing client lifecycle boundary, activate the narrow client state
   in each pane and relaunch only on success.

The scripts still own lifecycle and recovery, but do not collect config with a
second glob walker, merge env via repeated `source`, or implement another JSON
assembler. Cross-deployment operations are not one atomic CONFIG transaction;
failure after one successful native operation must report that partial result.
Missing ZIM host or bypass is incomplete when fresh client state is required.

Dependency restart stays an explicitly selected lifecycle operation. Config
membership alone does not authorize restarting the producer's service. A later
generic operation-composition contract should reuse the existing BINS/runtime
work, rather than smuggling `exec` handlers into config fragments.

## What changes from the pilot

| Pilot mechanism | Revised destination |
|---|---|
| Owner action descriptor | Existing typed consumer recipe/context plus native adapter |
| Per-member action descriptor | Actual native contribution artifact |
| Separate `order` on each action join | Native input order; no duplicate load-order field |
| `fuze.d/<id>.json` as a new membership system | Native input link, optionally reachable through a fuze.d exposure |
| `zim-import` kind | Existing ZIM install/import operation invoked by its owner |
| Generic `shell-source` kind | Selected shell projection with explicit activation semantics |
| Generic `exec` kind | Existing deployment/lifecycle commands and their composition authority |
| Read-only action planner | Native input inspection, assembly check, and concise domain status |

This is a proposed replacement direction. The pilot remains useful evidence for
exact references, installation/render separation, disabled state, and instance
isolation. Its source and tests are not silently reinterpreted as implementing
this draft.

## Next proof and remaining choices

Prove ENV first with two isolated producers and one consumer `etc/env.d/`:
local and linked inputs, explicit override order, native disable/enable, and
application-only service/shell projections. Demonstrate that foreign `DIR` cannot
redirect assembly and neither output acquires undeclared deployment plumbing.
Inspect winners; verify special-character serialization without executing input
data. Re-rendering must preserve installed controls, and failed assembly must
retain the prior valid aggregate through the existing transaction mechanism.

Then show ZIM using an explicit subset of those same values, and OpenCode accepting
a native JSON contribution through its current recipe. Exercise fresh shells and
existing shells separately. This gives three type examples before expanding the
generic contract.

Choices still requiring a concrete implementation proposal:

- Exact ENV fragment grammar and how current shell-expression values migrate.
- Smallest authored declaration for named env contributions and ZIM file selection;
  direct ZIM `env:` and existing ENV_LIST already cover part of the need.
- Whether SYSTEMD_ENV names service-selected files or manager-publication files;
  both should reference contributions, with the effects explicitly distinguished.
- Whether a fuze.d exposure is useful enough to install at all; native membership
  remains sufficient. Bundle membership should be added only for an actual need.
- How narrow shell activation records managed defaults and handles first adoption.
- Where OpenCode-native validation is obtained for the deployed version.

**Acceptance test for the architecture:** adding a contributor changes one native
input membership; assembly, inspection, and activation all consult that same
selection, and changing the contributor never changes Compfuzor's execution root.
