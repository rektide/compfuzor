---
type: Reference
title: Independent CONFIG definitions and explicit env.d contributions
description: Implemented complete CONFIG bindings, normal ZIM ownership, selected-spec remote delivery, and opt-in literal application ENV assembly.
resource: /doc/config/definitions.md
status: draft
generated: {by: 'model:openai/gpt-6.1-sol#xhigh', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed1c4aafeffectZuEW8rySlAgl
    title: lucky-engine — document proxy-first adoption and restored invocation-default preference
  - resource: /design/fuzings/proxy0.gpt61sol.md
    title: Concrete service/client selection, normal Zim import prerequisite, and isolated adoption evidence
  - resource: opencode://ses_ed21877fbffeK90YzBIZKC1jHb
    title: shiny-sailor — implement and verify complete CONFIGs, prepared-action alias transport, separate normal ZIM, and literal ENV contributions
  - resource: /design/fuzings/contract1.gpt6a.md
    title: Complete CONFIG identities and application/execution-context separation
  - resource: /design/fuzings/implementation0.gpt6a.md
    title: Predecessor implementation route and worker proof
  - resource: /doc/config/consumer-toolkit.md
    title: Existing contexts, operations, and publication semantics
  - resource: /library/filter_plugins/config_definitions.py
    title: Complete-definition packaging and collision checks
  - resource: /library/filter_plugins/env_compile.py
    title: ENV normalization, native contributions, and projection definitions
  - resource: /files/config-env.py
    title: Literal assignment grammar and consumer serializers
  - resource: /tests/integration/config_definitions.test.py
    title: Isolated generation, fanout, ENV projection, and actual proxy conditional-task evidence
  - resource: /tests/integration/zim_consumer.test.py
    title: Normal ZIM lifecycle beside another independent CONFIG
  - resource: /opencode-bus-proxy.src.pb
    title: Current user-owned proxy declarations preserved without adoption
  - resource: /vars/opencode.yaml
    title: Current shared port/discovery/watch inputs, read without revision
---

# Independent complete CONFIGs

`CONFIG_DEFINITIONS` is a named map of **complete ordinary CONFIG definitions**,
not partitions of one deployment-wide recipe namespace. Each has its own recipes,
inputs, contexts, default, validation hook, leaf paths, and installation owner.
They share one stock worker, processors, and bundled CONFIG runtime.

```yaml
CONFIG_DEFAULT: application
CONFIG_DEFINITIONS:
  application:
    configs:
      app.json:
        name: main
        processor: json-deep-merge
        inputs: [{glob: app.d/*.json, name: fragments, remote: true}]
    contexts:
      user: {scope: user, root: config, subpath: application}
    context: user
    install_owner: config
  another:
    etc: "{{ ETC }}/another"
    configs:
      app.json:
        name: main
        processor: json-deep-merge
        inputs: [{glob: app.d/*.json, name: fragments, remote: true}]
    contexts:
      user: {scope: user, root: config, subpath: another}
```

Settings: `configs`, `contexts`, `context`, `install_owner`, `etc`,
`disabled_suffix`, `transaction_validate`, `action_contexts`, and `audiences`.
These retain existing CONFIG semantics. `etc` changes canonical material, not the
shared engine or execution root. Top-level CONFIGS and existing companion settings
normalize as definition `default` through the same compiler. Empty CONFIGS is inert.
A single legacy definition retains fixed command symlinks, internal leaf names,
and ordinary install/status composition. Do not also author CONFIG_DEFINITIONS.default.

Specs live at `etc/config/<id>/spec.json`; `etc/config/instances.json` is a generated
deployment-local binding index, not a global registry or another authored manifest.
`etc/config.spec.json` is the default exposure. CONFIG_DEFAULT selects it; otherwise
`default` wins when present, then the lexically first definition.

```sh
bin/config-assemble.sh --definition application --context canonical
bin/config-install.sh --definition another --context user --dropins copy
bin/config-status.sh --definition application --json-array
bin/config-inputs.sh --definition another --context user put main/fragments /producer/input.json
```

`--spec PATH` and `--runner PATH` remain; --spec and --definition are exclusive.
Named definitions receive small `config-<id>-ACTION.sh` binding envelopes for
composition/status, not copied engines or recipe/context/strategy implementations.
They are symlinks through the shared runtime; the generated definition index binds
their spec while retaining alias identity for prepared actions. Names that would
collide with fixed commands or another definition's action alias are rejected.
Build-time canonical assembly runs a bound invocation per definition. Catalog and
audience-action operations carry exact per-definition specs.

Canonical output conflicts and identical/static consumer bindings across definitions
are rejected at compilation. Different runtime-dependent selectors can still alias:
avoid declaring them for the same output. Each CONFIG retains its own transaction;
there is no cross-definition transaction or candidate dependency DAG.

## Remote input delivery

Existing direct operations remain put/link, status, enable, disable, and remove.
Use `DEFINITION/INPUT`, or --definition/--spec, for ambiguous local names. Automatic
rebuilds use that same selected spec and runner.

```sh
bin/config-remote.mjs list
bin/config-remote.mjs put application/fragments /producer/settings.json
bin/config-remote.mjs put-matching /producer/settings.json \
  --definition application --definition another
```

put-matching resolves all filename-pattern matches before effects, bounded to selected
definitions of this deployment. `--target DEFINITION/INPUT` narrows selection. No match
or unknown explicit targets fail. Every destination is admitted before delivery;
each target then has its own mutation, validation/rebuild, and rollback. Later admitted
targets are still attempted after a failure; successes remain installed. This is not
a machine-wide search, trial-and-error fallback, application-schema discovery, or
enrolled-producer traversal. Remote delivery remains links; existing CONFIG input
operations supply copy/link consumer representations.

# Normal ZIM has its own CONFIG

zim.opt.pb declares complete definition `zim`, with unchanged local zimrc/zimenv
recipe/input names and `install_owner: zim`. ZIM_CONFIG_DEFINITION binds its normal
adapter to that exact spec. It still installs channels, projects loaders, builds
caches, handles imports/registry wiring, and reports activation health. Its ownership
does not suppress another definition's ordinary installer.

ZIM_CONFIG_CONTEXTS customizes this host's CONFIG contexts; existing top-level
CONFIG_CONTEXTS is a compatibility fallback. In mixed deployments use the former for
ZIM and the latter for top-level legacy CONFIGS. The ZIM spec records `configSpec`;
explicit --config-spec overrides it. This baseline generates one normal ZIM adapter
per deployment, not multiple automatic ZIM activation adapters. Independent CONFIGs
can nevertheless reuse normal ZIM recipe names.

# Explicit application ENV under etc/env.d

Adoption is **opt-in** with ENV_CONFIG: true (or the mapping below). Existing
playbooks/type-specific ENV templates stay on their current path until deliberately
adopted. In opt-in mode CONFIG alone writes DIR/env and DIR/env.export; filesystem
ENV rendering no longer also writes those aggregates.

```yaml
ENV_CONFIG:
  name: env
  projections:
    service.env: {files: [50-origin.env, 90-unit.env], format: env}
    client.zsh: {files: [60-client.env], format: env-zsh}
ENV:
  APPLICATION_SETTING: ordinary
ENV_PRIO:
  APPLICATION_SETTING: priority
ENV_CONTRIBUTIONS:
  50-origin.env:
    ORIGIN_ENDPOINT: "{{ origin_endpoint }}"
  60-client.env:
    CLIENT_ENDPOINT: "{{ client_endpoint }}"
  90-unit.env:
    CREDENTIAL_POINTER: "{{ unit_credential_pointer }}"
```

ENV_CONFIG also accepts normal contexts/context/install_owner. Its name owns a
complete definition; do not also declare that name in CONFIG_DEFINITIONS.
ENV_CONTRIBUTIONS maps native .env filenames to explicit value maps. ETC_FILES or
deliberate input links can supply native files too. Projections live under
etc/env-projections; their files select exact env.d contributions in authored order.
Missing selected files fail, without glob fallback or implicit enabling. Formats:
env, env-export, env-zsh.

ENV/ENV_LIST become env.d/00-local.env; ENV_PRIO/ENV_PRIO_LIST become
env.d/99-local-priority.env. Lists use exact-name lookup then uppercase fallback.
Mapping values override list values; priority wins last. Lists of values join with
spaces. Names are uppercased/validated; a mapping value true retains explicit
variable lookup semantics. Generic deployment variables are not implicitly injected.

Whole-collection recipes use `LC_ALL=C` filename order then reapply priority last.
Later values replace earlier keys and each resulting key is serialized once.
Exact-file projections select only their listed files: include the priority file
explicitly if wanted. Conditional ENV_PRIO additions before Compfuzor includes run
before normalization, retaining earlier priority keys.

## Literal grammar and projections

Inputs are assignment **data**, not programs: comments/blank lines and NAME=value.
Values can be JSON double-quoted strings, literal single-quoted strings without
embedded quotes, or unquoted values without whitespace/quotes/backslashes. No
execution or ambient expansion occurs. Dollar expressions/backticks are literal;
keep runtime shell expressions in native ZIM code. Invalid names and multiline/control
values fail.

- env uses systemd EnvironmentFile quoting, without shell expansion.
- env-export emits safely quoted literal shell exports.
- env-zsh defaults only **unset** variables, preserving deliberately empty values.
  It is a source-time projection, not managed existing-pane refresh; removed defaults
  are not automatically unset.

One shared standard-library Python reducer is deployed only when ENV processors are
selected; those definitions contribute python3. Normalization stays controller-side.
Candidate production/validation/publication uses the existing CONFIG transaction;
failed ENV assembly preserves prior valid aggregates.

## Execution context and consumers

env/env.export contain authored application values only. env.context separately
contains bound DIR/NAME/TYPE/etc. Generated bin helpers load application values and
then restore their execution context: inherited foreign DIR and authored application
DIR cannot redirect commands. Do not source a producer's complete env.export as a
selective projection; choose its native contribution/projection.

The helper retains the legacy envdefault preference for application defaults;
when that tool is installed, already-set invocation values (including empty ones)
win. Its existing direct-source fallback remains when envdefault is unavailable.
env.context is restored independently of that application-loading choice.

Systemd's default EnvironmentFile remains DIR/env, including ENV_CONFIG-only use.
**SYSTEMD_ENV still means manager publication**; it is not reinterpreted. Select a
service-specific projection through the explicit native unit interface:

```yaml
SYSTEMD_SERVICES:
  EnvironmentFile: "{{ ETC }}/env-projections/service.env"
```

Per-unit SYSTEMD_ROOTS can choose different files. Existing ZIM_ENV key selection
uses the opt-in normalized local application map. Direct ZIM modules/arrays/functions
and native sourced scripts remain normal ZIM material. An env-zsh projection can be
a normal module source; sequence its CONFIG assembly before ZIM cache construction.
There is no automatic ENV→ZIM candidate dependency.

# Verification and follow-on boundary

Isolated tests use local Ansible, temporary outputs, and real workers:

- config_definitions.test.py: same-named recipes/inputs/contexts in two complete
  CONFIGs; independent output/default/copy-link behavior; reverse declaration order;
  bound remote rebuild/fanout/failure isolation; ENV precedence/special characters,
  projections, validation retention, execution DIR isolation, and current proxy
  pre-include ENV_PRIO tasks with discovery/watch off/on combinations.
  Named user-audience installation is exercised end-to-end through prepared actions;
  frozen fanout bindings survive a spec replacement between target effects.
- zim_consumer.test.py: real normal ZIM beside independently installable JSON CONFIG,
  and existing loaders/caches/imports, user/system scopes, representations, bypass,
  failure, hostile DIR, and activation-spec cases.
- Existing compiler/context/command/graph/external-processor/remote/toolkit and
  transaction-fault tests provide regressions; typecheck, relevant Vitest, and lint
  are separate checks, not proof of live application compatibility.

The follow-on [proxy-first adoption](/design/fuzings/proxy0.gpt61sol.md) uses a
service-only EnvironmentFile projection and a client-only literal export. Its
normal phase-56 Zim module preserves runtime URL/argument defaults; build prepares
ENV before Rust, and the importer assembles ENV before host cache construction.
Shared ports, discovery modes, conditional ENV_PRIO, and watcher declarations
remain with their original owners.
proxy_env_adoption.test.py renders the real playbook and imports into an isolated
normal host. The lighter preservation fixture still checks pre-include tasks.
No live deployment, proxy/OpenCode build, systemd activation, or client/pane restart
is claimed. Wider fuze integration remains deferred.

The [native-root checkpoint](/design/fuzings/checkpoint0.gpt61sol.md) is experimental
work started before scope narrowing, not finished fuze integration. ENV winner-source
inspection, native OpenCode schema validation, managed existing-shell refresh,
dynamic cross-spec alias checks, and cross-definition dependencies remain gaps.
Legacy ENV's previous ordering/expansion semantics are not silently migrated.
