---
type: ImplementationPlan
title: Complete MCP-to-gen_config migration (behavior-preserving)
description: Finish wiring MCP onto the generic config subsystem so an MCP_CLIENT playbook produces a working config-mcp.sh assembly pipeline instead of half-migrated, broken hooks.
resource: /.design/config-mcp/init.0.md
tags: [compfuzor, mcp, config, subsystem, gen_config]
status: draft
generated: { by: model:opencode, at: 2026-08-11T03:10:00Z }
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
  - id: draft0
    resource: /.design/config-mcp/draft0.gpt56t.md
    title: Parallel draft on same scope
---

# Complete MCP-to-gen_config migration

## Situation

MCP used to own a dedicated merger (`mcp-config.sh`) that assembled `base.json` +
`etc/mcp/*.json` + `etc/mcp-disabled/*.json` into `etc/${MCP_CONF}`. The migration
in `90b53188` correctly made [`gen_mcp.tasks`](/tasks/compfuzor/gen_mcp.tasks)
delegate generic artifact creation to [`gen_config.tasks`](/tasks/compfuzor/gen_config.tasks),
but the wiring was left half-done:

- Scoped `CONFIG_KEY=mcp`, `CONFIG_EXT=json`, and the output path evaporate before
  bin/env rendering, so generated scripts can't find their config identity.
- The generic merger defaulted output to `etc/mcp.json`, not the former
  `etc/${MCP_CONF}` ([`config-json-merge.sh:14-18`](/files/config-json-merge.sh)).
- `mcp-install.ts`, `mcp-disable.sh`, and `status-config.sh` still call the
  obsolete `bin/config.sh` ([`mcp-install.ts:169-173`](/files/mcp-install.ts),
  [`mcp-disable.sh:47`](/files/mcp-disable.sh),
  [`status-config.sh:18-23`](/files/status/status-config.sh)).
- `config-json-merge.sh` has no `--check`, so the status reporter can't honor its
  contract.
- Generic `disable-mcp.sh` / `enable-mcp.sh` are emitted for MCP but use a
  move-between-directories model that conflicts with MCP's disabled-**last**
  override semantics.

This is a finish-the-migration task. No net-new features. The companion
[`draft0.gpt56t.md`](/.design/config-mcp/draft0.gpt56t.md) covers the same scope;
this wave turns it into an editable step list.

## Goal

For an `MCP_CLIENT` playbook, generation yields a working pipeline identical in
observable behavior to the former `mcp-config.sh`:

```text
etc/base.json
etc/mcp/*.json
etc/mcp-disabled/*.json
        |
        v
bin/config-mcp.sh   (json-merge)
        |
        v
etc/${MCP_CONF}
```

Installing/disabling an MCP fragment rebuilds that output; status can report
drift without writing.

## Scope

**In:** retain the `gen_mcp -> gen_config` delegation; preserve `MCP_CONF` output;
preserve MCP disabled-last override semantics; keep `mcp-disable.sh` +
`mcp-install.ts`; make generated config bins self-contained (retained scoped
`CONFIG_*`); fix stale rebuild/status hooks; add `--check` to the JSON merger;
add integration tests.

**Out:** OpenCode `etc_d` assembly; a `CONFIGS` collection / general multi-instance
model; combining multiple source dirs into one generic job; `ETC_D` / `fs_d.tasks`
retirement; redesigning MCP enable/disable; unrelated `opencode.src.pb` duplicate
entries.

## Design

### 1. Make config bins self-contained

Resolve the config identity **inside the scoped import** and attach a small
`early` body to each generated config bin so it survives downstream rendering:

```sh
export CONFIG_KEY=mcp
export CONFIG_EXT=json
export CONFIG_OUTPUT="${DIR}/etc/${MCP_CONF}"
```

This reuses the established `BINS.early` execution point. The package-wide
`env.export` keeps ordinary MCP settings (`MCP_TARGET`, `MCP_WRAPPER`) but stops
being responsible for the generator's scoped identity. The values must be
templated while `gen_config`'s task-local scope is live, per the
[task-local rendering boundary](/library/README.md).

### 2. Preserve MCP output via explicit `CONFIG_OUTPUT`

`gen_mcp.tasks` already passes `CONFIG_KEY/merge/ext`; add an explicit
`CONFIG_OUTPUT: "${DIR}/etc/{{ MCP_CONF }}"` and **fail validation when `MCP_CONF`
is undefined** for an active `MCP_CLIENT` (today it silently mis-writes).

### 3. Stop emitting conflicting generic toggles for MCP

Add a narrow default-on switch so `gen_config` can skip the generic
`disable-<key>.sh` / `enable-<key>.sh` bins for MCP. MCP keeps only
`mcp-disable.sh` with its override model. Do **not** reinterpret the JSON
merger's disabled-last behavior.

### 4. Remove late `{{ CONFIG_KEY }}` from generic toggle hooks

Even though MCP suppresses them, fix `config-disable.sh` /
`config-enable.sh` rebuild calls to use the runtime `key` variable
(`"${dir}/bin/config-${key}.sh"`), aligning them with scoped generation.

### 5. Repair MCP rebuild hooks

Point `mcp-disable.sh`, `mcp-install.ts`, and (if retained) `mcp-install.sh` at
`bin/config-mcp.sh`. No MCP-specific enable command is added here.

### 6. Real JSON status checks

Derive the reporter's script path from runtime `CONFIG_KEY`
(`script="$DIR/bin/config-${CONFIG_KEY}.sh"`) and add the `--check`/`-q` contract
to `config-json-merge.sh`: exit 0 when current, 1 on drift, never write in check
mode, show diff unless `-q`. Keep the singleton `status-config.sh` (multi-config
status naming is deferred).

## File-by-file changes

| File | Change |
|---|---|
| `tasks/compfuzor/gen_config.tasks` | attach retained `CONFIG_*` to generated bins' `early`; add toggle-skip switch |
| `vars/common.yaml` | config subsystem contrib honors toggle-skip; document default-on |
| `tasks/compfuzor/gen_mcp.tasks` | pass explicit `CONFIG_OUTPUT` from `MCP_CONF`; add `MCP_CONF` validation |
| `files/config-json-merge.sh` | add `--check`/`-q`; honor `CONFIG_OUTPUT`, `CONFIG_EXT` |
| `files/config-disable.sh` / `config-enable.sh` | rebuild via `config-${key}.sh` |
| `files/mcp-disable.sh` | call `config-mcp.sh` |
| `files/mcp-install.ts` / `mcp-install.sh` | call `config-mcp.sh` |
| `files/status/status-config.sh` | `config-${CONFIG_KEY}.sh` |
| `tests/integration/config_mcp.test.py` | new behavior-characterizing tests |

## Validation

- `ansible-playbook opencode.src.pb --syntax-check` stays green.
- New `tests/integration/config_mcp.test.py` asserts: `config-mcp.sh` emitted;
  rendered config/status bins retain MCP `CONFIG_*`; output targets `MCP_CONF` not
  `mcp.json`; no generic `disable-mcp.sh`/`enable-mcp.sh`; `mcp-disable.sh` and
  installer target `config-mcp.sh`.
- `tests/lookup_plugins/merge_subsys.test.py` (23 passing) stays green.
- Run the `.test-agent/multi-gen-config` harness (or a focused MCP variant) to
  confirm scoped values persist into rendered bins.

## Commit plan

1. **Characterize** — add `tests/integration/config_mcp.test.py` describing target
   behavior; it fails against current code.
2. **Self-contain config bins** — `gen_config` retains `CONFIG_*` + toggle-skip
   switch; fix generic toggle rebuild hooks.
3. **Preserve MCP output** — `gen_mcp` explicit `CONFIG_OUTPUT` + `MCP_CONF`
   validation.
4. **Repair MCP hooks + status** — `mcp-disable.sh`/`mcp-install.*`/`status-config.sh`
   point at `config-mcp.sh`; JSON `--check`.
5. **Commit + run** tests; smoke-run `opencode.src.pb` with bypasses.
