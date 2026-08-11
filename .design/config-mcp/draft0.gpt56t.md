---
type: ImplementationPlan
title: Integrate MCP with the config generator
description: Complete the existing MCP-to-gen_config migration while preserving the former MCP behavior.
resource: /.design/config-mcp/draft0.gpt56t.md
tags: [compfuzor, mcp, config, subsystem]
status: draft
generated: { by: model:gpt56t, at: 2026-08-11T02:27:53Z }
stale_after: 2026-09-10
sources:
  - id: gen-mcp
    resource: /tasks/compfuzor/gen_mcp.tasks
    title: MCP artifact generator
  - id: gen-config
    resource: /tasks/compfuzor/gen_config.tasks
    title: Generic config artifact generator
  - id: config-subsystem
    resource: /vars/common.yaml
    title: Static config subsystem contribution
  - id: old-mcp-merger
    resource: git:90b53188%5E:files/mcp-config.sh
    title: MCP merger before delegation to gen_config
---

# Integrate MCP with the config generator

## Situation

MCP formerly owned a dedicated merger that combined `base.json`, active MCP
fragments, and disabled overrides into `etc/${MCP_CONF}`. The recent migration
correctly changed [`gen_mcp.tasks`](/tasks/compfuzor/gen_mcp.tasks) to delegate
generic artifact creation to [`gen_config.tasks`](/tasks/compfuzor/gen_config.tasks),
but the integration was not completed end to end.

The scoped import currently specializes artifact names such as
`config-mcp.sh`, then loses `CONFIG_KEY=mcp`, `CONFIG_EXT=json`, and the output
path before environment and bin rendering. The generic merger also defaults to
`etc/mcp.json` instead of the former `etc/${MCP_CONF}`. MCP install, disable,
and status hooks still look for the obsolete `bin/config.sh`.

This wave plans a behavior-preserving completion of that migration. It does not
design multi-config jobs or integrate OpenCode's new `etc_d` fragments.

## Goal

An `MCP_CLIENT` playbook uses the generic config subsystem to produce a working
MCP assembly pipeline with the same observable behavior as the former
MCP-specific merger:

```text
etc/base.json
etc/mcp/*.json
etc/mcp-disabled/*.json
        |
        v
bin/config-mcp.sh
        |
        v
etc/${MCP_CONF}
```

Installing or disabling an MCP fragment rebuilds that output. Status can check
for drift without modifying it.

## Scope

### Included

- Retain `gen_mcp.tasks -> gen_config.tasks` delegation.
- Preserve `MCP_CONF` as the assembled output filename.
- Preserve MCP's disabled-last JSON override semantics.
- Retain MCP-specific `mcp-disable.sh` and `mcp-install.ts` tooling.
- Make generated config bins retain scoped `CONFIG_*` values through rendering.
- Repair stale rebuild and status hooks.
- Add integration coverage around generation, rendering, and runtime behavior.

### Deferred

- OpenCode `etc_d` assembly.
- A `CONFIGS` collection or general multi-instance config model.
- Combining multiple source directories into one generic config job.
- Migrating or removing legacy `ETC_D` and `fs_d.tasks`.
- Redesigning MCP enable/disable behavior.
- Unrelated duplicate entries in `opencode.src.pb`.

## Intended Artifacts

For an MCP client, generation should contribute:

| Artifact | Purpose |
|---|---|
| `bin/config-mcp.sh` | Merge MCP JSON fragments into `etc/${MCP_CONF}` |
| `bin/mcp-disable.sh` | Create MCP `enabled:false` overrides and rebuild |
| `bin/mcp-install.ts` | Install a server fragment and rebuild |
| `bin/status-config.sh` | Check the MCP assembly for drift |
| `etc/mcp/` | Active MCP fragments |
| `etc/mcp-disabled/` | Disabled-last override fragments |

The generic `disable-mcp.sh` and `enable-mcp.sh` bins should not be generated
for MCP. Their move-between-directories model conflicts with MCP's override
model: the JSON merger deliberately includes `mcp-disabled` last.

## Integration Design

### Retain scoped values on each bin

The config subsystem should resolve a small config-bin defaults block while the
scoped import is active and attach it to each generated config bin's `early`
body:

```sh
export CONFIG_KEY=mcp
export CONFIG_EXT=json
export CONFIG_OUTPUT="${DIR}/etc/opencode.json"
```

The exact output filename comes from `MCP_CONF`; `opencode.json` above is the
current OpenCode value, not a new generic default.

This uses the established `BINS.early` execution point rather than adding a
second environment-file system. The values must be resolved before leaving the
task-local scope, following the task-local rendering boundary documented in
[`library/README.md`](/library/README.md#templates--rendering).

The shared package `env.export` may still contain ordinary MCP settings such as
`MCP_TARGET` and `MCP_WRAPPER`. It must no longer be responsible for retaining
the config generator's scoped identity.

### Preserve MCP output selection

`gen_mcp.tasks` should invoke `gen_config.tasks` with an explicit output derived
from `MCP_CONF`, equivalent to:

```yaml
CONFIG_KEY: mcp
CONFIG_MERGE: json-merge
CONFIG_EXT: json
CONFIG_OUTPUT: "${DIR}/etc/{{ MCP_CONF }}"
```

Missing `MCP_CONF` for an active MCP client should fail validation rather than
silently writing a different filename.

### Keep only MCP-compatible toggle tooling

Add a narrowly named config-generation switch whose default preserves current
generic behavior, but which lets `gen_mcp.tasks` omit generic enable/disable
bins. MCP then keeps only `mcp-disable.sh` and its existing override semantics.

Do not reinterpret the generic JSON merger's disabled-last behavior in this
work. Other merge strategies exclude disabled fragments; MCP intentionally
uses disabled JSON records as higher-precedence overrides.

### Remove late Jinja dependence from generic toggle hooks

Even though MCP will suppress the generic toggle bins, fix their rebuild call
to use the runtime `key` variable:

```sh
"${dir}/bin/config-${key}.sh"
```

This removes the existing late `{{ CONFIG_KEY }}` dependency and makes the
generic config contribution internally consistent with its scoped generation
contract.

### Repair MCP rebuild hooks

Update MCP-owned hooks to invoke `bin/config-mcp.sh`:

- [`mcp-disable.sh`](/files/mcp-disable.sh)
- [`mcp-install.ts`](/files/mcp-install.ts)
- [`mcp-install.sh`](/files/mcp-install.sh), if retained as a supported sibling

Do not add an MCP-specific enable command in this migration.

### Make JSON status checks real

Keep the existing singleton `status-config.sh`; multi-config status naming is
deferred. Its config script path should be derived from runtime `CONFIG_KEY`:

```sh
script="$DIR/bin/config-${CONFIG_KEY}.sh"
```

Add the same `--check` and `-q` contract already implemented by
[`config-yaml-list.sh`](/files/config-yaml-list.sh) and
[`config-block-in-file.sh`](/files/config-block-in-file.sh) to
[`config-json-merge.sh`](/files/config-json-merge.sh):

- exit `0` when output is current;
- exit `1` on drift;
- never modify output in check mode;
- show the diff unless quiet.

## Commit Plan

### 1. Characterize the MCP config contract

Add `tests/integration/config_mcp.test.py` using a temporary local Ansible
playbook, following the existing integration-test pattern.

The initial assertions should describe the target behavior and fail against the
current implementation:

- scoped generation emits `config-mcp.sh`;
- rendered config and status bins contain retained MCP config defaults;
- output targets `MCP_CONF`, not `mcp.json`;
- no generic `disable-mcp.sh` or `enable-mcp.sh` is emitted;
- `mcp-disable.sh` and the installer target `config-mcp.sh`.

### 2. Make generic config bins self-contained

Change the config contribution/generator boundary so every generated config bin
receives resolved `CONFIG_KEY`, `CONFIG_EXT`, and `CONFIG_OUTPUT` defaults in
its `early` body. Add the default-on switch for generic toggle bins and remove
late Jinja use from their rebuild hooks.

Keep the legacy single-config call shape working for Zim and interception-tools.

### 3. Complete MCP delegation

Pass the MCP output path based on `MCP_CONF`, disable generic toggle-bin
generation for MCP, and update MCP-owned rebuild hooks to `config-mcp.sh`.

At this commit, MCP generation should no longer depend on global
`CONFIG_KEY`, `CONFIG_EXT`, or `CONFIG_OUTPUT` values surviving the import.

### 4. Implement JSON check mode and repair status dispatch

Port the established `--check`/`-q` behavior into the JSON merger and make
`status-config.sh` dispatch to `config-${CONFIG_KEY}.sh`.

Extend the integration test to execute clean and drift checks and assert that
check mode does not mutate the assembled file.

### 5. Verify real MCP client playbooks

Run syntax checks for:

```sh
ansible-playbook opencode.src.pb --syntax-check
ansible-playbook amp.opt.pb --syntax-check
ansible-playbook mcp-cli.src.pb --syntax-check
```

Run the focused integration test and existing merge tests. Use a temporary
fixture to execute the rendered MCP scripts rather than writing into `/opt` or
`/usr/local/src`.

## Acceptance Criteria

- An MCP client renders `config-mcp.sh` with `CONFIG_KEY=mcp`,
  `CONFIG_EXT=json`, and `CONFIG_OUTPUT` ending in its declared `MCP_CONF`.
- Running `config-mcp.sh` merges base, active, and disabled override JSON into
  `etc/${MCP_CONF}`.
- `mcp-disable.sh` rebuilds through `config-mcp.sh`.
- The active MCP installer rebuilds through `config-mcp.sh`.
- MCP does not expose the incompatible generic `disable-mcp.sh` and
  `enable-mcp.sh` pair.
- `status-config.sh` checks `config-mcp.sh --check` and reports clean/drift
  without changing the output.
- Existing non-MCP users of `gen_config.tasks` retain their default generic
  enable/disable bins.
- OpenCode, Amp, and MCP CLI playbooks pass syntax checks.
- The focused integration test and existing lookup/filter tests pass.

## Risks And Guardrails

- **Early-body ordering:** `_bin` sources package environment before executing
  `early`; the retained config defaults must therefore overwrite absent or
  unrelated shared `CONFIG_*` values deliberately.
- **Template lifetime:** resolve task-local values before storing BINS facts.
  A test must render the bins after the import scope has ended.
- **MCP disabled semantics:** do not "fix" disabled-last merging; MCP relies on
  it for override records.
- **Generic regressions:** the toggle-bin switch defaults on, and existing Zim
  and interception-tools generation receives characterization coverage or at
  least artifact assertions.
- **Scope creep:** do not make MCP and `etc_d` both write `opencode.json` in this
  work. That requires the separate layered-source design.

## Open Questions

1. Is [`mcp-install.sh`](/files/mcp-install.sh) still supported, or can its stale
   rebuild hook be left documented as dead code for a later removal?
2. Should a missing `MCP_CONF` fail in `gen_mcp.tasks`, or should MCP retain a
   documented default? Current MCP client playbooks all declare it.

Neither question blocks the core integration design.

## Cross-References

- [`doc/subsys.md`](/doc/subsys.md#the-gen_tasks-pattern) defines the current
  `gen_*` contribution pattern that this migration retains rather than
  replacing.
- [`doc/arch.md`](/doc/arch.md#runtime-instances-subsystem) distinguishes
  subsystem-owned state from shared artifacts and explains why scoped config
  identity must be carried in generated records rather than inferred later.
- [`doc/intent-prefix-system.md`](/doc/intent-prefix-system.md#config) records a
  future `fn_config` seam for multi-config schemes. This plan intentionally
  stops short of that seam and repairs only the existing `gen_config` path.
- [`library/README.md`](/library/README.md#templates--rendering) documents the
  need to resolve task-local template values before downstream rendering.
