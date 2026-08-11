---
type: DesignProposal
title: Converge MCP on repeatable config generation
description: Replace MCP-specific override behavior with generic suffix-based config toggles and make gen_config safely repeatable.
resource: /.design/config-mcp/draft1.gpt56t.md
tags: [compfuzor, mcp, config, subsystem, cli]
status: draft
generated: { by: model:gpt56t, at: 2026-08-11T21:33:10Z }
stale_after: 2026-09-11
sources:
  - id: prior-wave
    resource: /.design/config-mcp/draft0.gpt56t.md
    title: Behavior-preserving MCP integration plan
  - id: gen-mcp
    resource: /tasks/compfuzor/gen_mcp.tasks
    title: MCP artifact generator
  - id: gen-config
    resource: /tasks/compfuzor/gen_config.tasks
    title: Generic config artifact generator
  - id: config-subsystem
    resource: /vars/common.yaml
    title: Static config subsystem contribution
---

# Converge MCP on repeatable config generation

## What Changed From Draft 0

[`draft0.gpt56t.md`](/.design/config-mcp/draft0.gpt56t.md) assumed that the
reformed MCP subsystem should preserve the old MCP merger's disabled-override
behavior. That is not required.

This revision instead treats MCP as the first demanding consumer of a better
generic config subsystem:

- MCP adopts generic config enable/disable behavior.
- Disabled state is encoded in the filename, not a second directory.
- MCP-specific disable logic is removed.
- `gen_config.tasks` becomes safely callable more than once.
- A second config-like subsystem must be able to reuse the same interface
  without adding subsystem-specific scripts.

This is still an integration plan, but it permits breaking the old MCP behavior
where doing so makes the generic config model smaller and more coherent.

## Current State

Some of the MCP reform has already landed:

- [`gen_mcp.tasks`](/tasks/compfuzor/gen_mcp.tasks) imports
  [`gen_config.tasks`](/tasks/compfuzor/gen_config.tasks) with scoped MCP values.
- The generic config contribution creates key-qualified merger, disable, and
  enable bins.
- [`config-json-merge.sh`](/files/config-json-merge.sh) was extracted from the
  old MCP-specific merger.
- `CONFIG_EXT` was added to the generic toggle scripts.

The delegation itself is therefore not a new implementation step. It is the
partially completed starting point.

The remaining model is inconsistent:

| Strategy | Active fragments | "Disabled" fragments | Effective behavior |
|---|---|---|---|
| YAML list | `etc/<key>/*.<ext>` | `etc/<key>-disabled/*.<ext>` | excluded |
| Block in file | `etc/<key>/*.<ext>` | `etc/<key>-disabled/*.<ext>` | excluded |
| JSON merge | `etc/<key>/*.json` | `etc/<key>-disabled/*.json` | merged last |

The generic enable/disable commands move files between directories. That works
for exclusion, but not for MCP's JSON overrides. MCP consequently also carries
`mcp-disable.sh`, giving it two incompatible disable interfaces.

Separately, repeated scoped calls specialize artifact names but do not retain
per-call runtime values. All generated bins later source one shared
`env.export`, while `CONFIG_KEY`, `CONFIG_EXT`, and `CONFIG_OUTPUT` remain
singular globals. Status is also a singleton named `status-config.sh`.

## Proposed Model

### One directory, suffix-based state

Every config instance owns one fragment directory:

```text
etc/mcp/
  permission.json
  mdns.json
  openai-codex.json.disabled
```

The fixed state transition is:

```text
<stem>.<ext> <-> <stem>.<ext>.disabled
```

All merger strategies read only `*.<ext>`. A disabled file naturally falls out
of the active glob because its final suffix is `.disabled`.

Consequences:

- Remove `<key>-disabled/` from generic `ETC_DIRS` contributions.
- Remove disabled-directory input from every merger.
- Remove MCP's disabled-last override semantics.
- Remove MCP-specific `mcp-disable.sh`.
- Generate the same generic enable and disable tools for MCP as for every other
  config instance.

Disabling an MCP fragment now means excluding that fragment. It may reveal a
lower-precedence value from another fragment or the base document; it no longer
injects an `enabled:false` override. That behavior change is accepted.

### Common CLI tools

Each config invocation generates discoverable, key-qualified commands from the
same shared templates:

```text
bin/config-mcp.sh
bin/disable-mcp.sh
bin/enable-mcp.sh
bin/status-config-mcp.sh
```

The toggle commands operate as follows:

```text
disable-mcp.sh <patterns...>
  permission.json -> permission.json.disabled

enable-mcp.sh <patterns...>
  permission.json.disabled -> permission.json
```

Required CLI behavior:

- accept explicit paths and the existing filename/stem pattern interface;
- match only the configured extension;
- preflight all destination collisions before moving any files;
- fail if no arguments are supplied;
- report unmatched patterns;
- perform all renames, then invoke `config-mcp.sh` once;
- use the same implementation for every config key.

The implementation should remain two shared templates, parameterized into
per-key bins. A new monolithic `config-toggle` command is unnecessary.

### Callable config contract

`gen_config.tasks` remains callable through scoped `import_tasks` variables:

```yaml
- import_tasks: gen_config.tasks
  vars:
    CONFIG_KEY: mcp
    CONFIG_MERGE: json-merge
    CONFIG_EXT: json
    CONFIG_OUTPUT: "${DIR}/etc/{{ MCP_CONF }}"
    CONFIG_BASE: "${DIR}/etc/base.json"
```

The callable contract is:

| Input | Meaning |
|---|---|
| `CONFIG_KEY` | Instance identity, fragment directory, and bin-name suffix |
| `CONFIG_MERGE` | Finite merger implementation name |
| `CONFIG_EXT` | Active fragment extension |
| `CONFIG_OUTPUT` | Assembled output path |
| `CONFIG_BASE` | Optional base input; absent means no base document |

`CONFIG_BASE` replaces the JSON merger's global hard-coded `etc/base.json`.
Without that change, a second JSON config instance could accidentally ingest
an unrelated application's base document.

### Per-instance generated records

Every call must fully specialize its generated artifacts before task scope
ends. Each generated bin record carries resolved defaults in its `early` body:

```sh
export CONFIG_KEY=mcp
export CONFIG_EXT=json
export CONFIG_OUTPUT="${DIR}/etc/opencode.json"
export CONFIG_BASE="${DIR}/etc/base.json"
```

Generated names are also instance-qualified:

- `config-<key>.sh`
- `disable-<key>.sh`
- `enable-<key>.sh`
- `status-config-<key>.sh`

`STATUSES` receives the instance-qualified status name. Generic `CONFIG_*`
names are removed from `ENV_LIST`; the shared package environment is not the
storage location for callable task parameters.

`ETC_DIRS` should use append-unique behavior so authored and generated requests
for the same fragment directory do not duplicate work.

### Repeatability invariant

After two imports such as `mcp` and `policy`, the final shared artifacts must
contain two independent sets:

```text
etc/mcp/
etc/policy/

bin/config-mcp.sh
bin/disable-mcp.sh
bin/enable-mcp.sh
bin/status-config-mcp.sh

bin/config-policy.sh
bin/disable-policy.sh
bin/enable-policy.sh
bin/status-config-policy.sh
```

Executing either set must use its own key, extension, base, and output even
after both scoped imports have ended. Neither set may depend on whichever
`CONFIG_*` variables happen to be globally visible later.

This makes delegation scale to another subsystem shaped like MCP:

```text
gen_new_subsystem.tasks
  -> contributes domain-specific fragments/tooling
  -> imports gen_config.tasks with one scoped config contract
  -> receives the common merge/toggle/status CLI
```

## MCP Integration

After the generic enhancement, MCP becomes a thin contributor:

1. MCP server packages continue emitting `etc/mcp.json` source records.
2. An MCP client provides `MCP_CONF`, `MCP_TARGET`, and wrapper settings.
3. `gen_mcp.tasks` contributes `mcp-install.ts` and imports `gen_config.tasks`
   for key `mcp`.
4. Generic config contributes the fragment directory and all four common CLI
   bins.
5. `mcp-install.ts` writes an active `*.json` fragment and invokes
   `config-mcp.sh`.

Remove:

- `mcp-disable.sh` from MCP BINS;
- `mcp-disabled` from MCP and client playbook directories;
- generic JSON disabled-last input;
- stale `config.sh` rebuild hooks.

The installer remains MCP-specific because it converts server package metadata
into each client's wrapper shape. Merge, toggle, and status behavior are fully
generic.

## Implementation Wave

### 1. Characterize repeatable generation

Add an integration test that imports `gen_config.tasks` twice with distinct
keys, extensions, bases, and outputs. Render all generated bins after both
imports have ended.

Assert:

- all bin and status names are key-qualified;
- each script contains only its own resolved defaults;
- no generic `CONFIG_*` names are added to `ENV_LIST`;
- only one directory per key is contributed;
- invoking one merger cannot write the other's output.

This is the architectural acceptance test, not merely an MCP fixture.

### 2. Make config generation instance-complete

Update the config contribution and `gen_config.tasks` so names and runtime
defaults are resolved into records inside the scoped call. Qualify status names,
deduplicate directories, and remove config call parameters from `ENV_LIST`.

Keep existing single-call playbooks working through the same callable contract.

### 3. Replace directory toggles with suffix toggles

Rewrite the shared enable/disable templates around `.<ext>.disabled`. Add
collision preflight and one rebuild after all moves. Update YAML, block, and JSON
mergers to consume active files only.

Delete generated `<key>-disabled` directory contributions.

### 4. Parameterize optional base input and JSON check mode

Replace hard-coded `base.json` discovery with `CONFIG_BASE`. Implement the same
`--check`/`-q` contract used by the existing YAML and block mergers.

Make each generated status bin invoke its matching key-qualified merger.

### 5. Collapse MCP onto generic config behavior

Pass MCP's output and optional base explicitly, remove its custom disable bin,
and update the installer rebuild hook. Remove `mcp-disabled` declarations from
MCP client playbooks.

Add an MCP integration scenario proving install, disable, enable, merge, and
status behavior through the generic bins.

### 6. Verify current config consumers

Run focused tests and syntax checks for MCP clients and current direct config
users:

```sh
ansible-playbook opencode.src.pb --syntax-check
ansible-playbook amp.opt.pb --syntax-check
ansible-playbook mcp-cli.src.pb --syntax-check
ansible-playbook zim.opt.pb --syntax-check
ansible-playbook interception-tools.srv.pb --syntax-check
```

## Acceptance Criteria

- Config state is represented solely by `.<ext>` versus `.<ext>.disabled`.
- All merge strategies ignore disabled files in the same way.
- Generic per-key disable and enable commands work for MCP.
- MCP no longer contributes `mcp-disable.sh` or uses `mcp-disabled/`.
- MCP output is selected explicitly through its config invocation.
- JSON supports non-mutating drift checks.
- Two scoped `gen_config.tasks` imports produce independently executable bins
  and status reporters.
- A second subsystem can delegate to `gen_config.tasks` without adding custom
  merge, toggle, or status scripts.
- Existing direct config consumers pass focused generation checks and syntax
  checks.

## Non-Goals

- Multiple source directories feeding one output.
- Dependency ordering between config instances.
- A `CONFIGS` collection or loop-based front end.
- OpenCode `etc_d` integration.
- Legacy `ETC_D` migration.
- Automatic migration of already-installed `<key>-disabled/` contents.

## Risks

- Existing disabled MCP override files will not be migrated automatically; this
  is an accepted breaking change.
- Qualifying status names changes generated artifacts for current config users;
  tests must verify status composition discovers the new names.
- Shell pattern behavior can cause accidental broad renames; collision
  preflight and extension filtering are mandatory.
- `CONFIG_BASE` must be optional without accidentally rendering an undefined
  value into generated shell.
- Resolving scoped values too late recreates the current bug; the two-import
  render-and-execute test is the guardrail.

## Open Questions

1. Should `CONFIG_BASE` accept one path only or an ordered list? One optional
   path is sufficient for this wave and avoids introducing layered sources.
2. Should enable/disable accept regular expressions or shell globs? Preserve
   the current user-facing matching behavior unless tests demonstrate that it
   is ambiguous.
3. Should stale `mcp-install.sh` be updated alongside `mcp-install.ts` or
   removed as dead code? Decide from repository references during
   implementation.

## Cross-References

- [`draft0.gpt56t.md`](/.design/config-mcp/draft0.gpt56t.md) is the superseded
  behavior-preserving proposal; its diagnosis remains useful, but its MCP
  override-preservation constraint does not.
- [`doc/subsys.md`](/doc/subsys.md#the-gen_tasks-pattern) defines the `gen_*`
  contribution pattern retained by both MCP and future config-like subsystems.
- [`doc/arch.md`](/doc/arch.md#runtime-instances-subsystem) leaves room for
  multiple instances of one subsystem type; repeatable scoped config calls are
  a concrete application of that direction.
- [`doc/intent-prefix-system.md`](/doc/intent-prefix-system.md#config) proposes
  a future `fn_config` seam for richer multi-config schemes. This wave makes the
  current callable generator safe but does not add that larger front end.
- [`library/README.md`](/library/README.md#templates--rendering) documents the
  task-local rendering boundary that requires per-call defaults to be resolved
  into generated records.
