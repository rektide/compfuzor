---
type: Design
title: Reform MCP onto the gen_config subsystem
description: Finish the half-done MCP → config migration so MCP uses gen_config without regressions, no new feature surface.
tags: [compfuzor, config, mcp]
status: draft
generated: { by: agent, at: 2026-08-10 }
sources:
  - id: prior-assessment
    title: Two independent subagent assessments of gen_config multi-instance safety
    author: agent
---

# Reform MCP onto gen_config

## What's up

`gen_mcp.tasks` was recently refactored to delegate to a new generic
`gen_config.tasks` (commit `quvrormn`, "gen_mcp: delegate config management to
gen_config, keep only MCP-specifics"). The intent was to retire the MCP-specific
`mcp-config.sh`/`vars_mcp.tasks` in favor of the generic config subsystem.

That delegation is **mechanically wired but not operationally correct**. Two
independent assessments (this session) ran a scoped two-import harness and
confirmed: the generic subsystem can emit distinct bin *names* and *directories*,
but it cannot retain per-instance runtime state, and the MCP path specifically
regressed. This wave is about finishing that migration — getting old MCP
behavior onto the new subsystem — without inventing a new multi-config feature
model.

## The concrete regressions to fix

These are the failures that make "MCP uses gen_config" untrue today:

1. **MCP's config values don't survive import.**
   `gen_mcp.tasks:72-78` imports `gen_config.tasks` with scoped
   `CONFIG_KEY=mcp`, `CONFIG_EXT=json`. Those vars are task-local and vanish
   after the import. By the time `fs_env.tasks` renders `env.export` and
   `bins.tasks` renders script bodies, only the global defaults remain:
   `CONFIG_EXT: conf`, `CONFIG_KEY: undefined`, and a single generic
   `CONFIG_OUTPUT`. See [harness result](#harness-result) below.

2. **MCP output target regressed to `mcp.json`.**
   The old `mcp-config.sh` wrote `${DIR}/etc/${MCP_CONF}` where
   `MCP_CONF: opencode.json` ([`opencode.src.pb:20`](/opencode.src.pb)). The
   generic merger reads only `CONFIG_OUTPUT`, defaulting to
   `${DIR}/etc/${CONFIG_KEY}.${CONFIG_EXT}` = `etc/mcp.json`. `MCP_CONF` is now
   dead config. OpenCode expects `opencode.json`.

3. **Stale `bin/config.sh` rebuild hooks.**
   Generation now produces `config-mcp.sh`, but MCP tooling still calls the old
   name: [`files/mcp-disable.sh:47`](/files/mcp-disable.sh) and
   [`files/mcp-install.ts:169-173`](/files/mcp-install.ts). Installing or
   disabling an MCP entry never rebuilds the assembled config.

4. **`config-disable.sh`/`config-enable.sh` late-render `{{CONFIG_KEY}}`.**
   [`files/config-disable.sh:53`](/files/config-disable.sh) and
   [`files/config-enable.sh:51`](/files/config-enable.sh) template
   `{{CONFIG_KEY}}` into the rebuild invocation. Bin *bodies* render late in
   [`bins.tasks:48-62`](/tasks/compfuzor/bins.tasks), after the MCP import's
   scoped vars are gone — so the rebuild name resolves wrong (or fails).

5. **Conflicting disable mechanisms.**
   `gen_config` contributes generic `disable-mcp.sh` (moves the fragment into
   `mcp-disabled/`). `gen_mcp` also contributes `mcp-disable.sh` (writes an
   `{"enabled": false}` override). The JSON merger merges disabled-last
   ([`config-json-merge.sh:19,31`](/files/config-json-merge.sh)), so a *moved*
   full fragment stays active — generic disable is semantically wrong for
   json-merge jobs. Generic `enable-mcp.sh` also can't undo an MCP-style
   override because the active file still exists
   ([`config-enable.sh:38-48`](/files/config-enable.sh)).

### Harness result

A scoped two-import vars harness (`.test-agent/multi-gen-config/`) produced,
after both imports completed:

```json
{
  "bins": ["config-mcp.sh", "disable-mcp.sh", "enable-mcp.sh",
           "status-config.sh", "config-etc_d.sh", ...],
  "env_list": ["CONFIG_KEY", "CONFIG_EXT", "CONFIG_OUTPUT"],
  "etc_dirs": ["mcp", "mcp-disabled", "etc_d", "etc_d-disabled"],
  "late_config_key_defined": false,
  "late_config_ext": "conf",
  "late_config_output": "${DIR}/etc/${CONFIG_KEY}.${CONFIG_EXT}",
  "statuses": ["status-config.sh", "status-config.sh"]
}
```

Names accumulate; per-instance runtime state does not.

## Goal / non-goals

**Goal:** MCP on OpenCode assembles `base.json + mcp/*.json + mcp-disabled/*.json`
into `etc/opencode.json`, with working install/disable rebuild hooks, using the
generic config subsystem — preserving the pre-generalization MCP behavior.

**Non-goals (explicitly deferred):**

- Multiple config jobs writing one combined document (the `CONFIGS:` collection
  model). One OpenCode job only.
- `etc_d` as a config layer (it stays an `ETC_FILES` dir for now).
- `ETC_D` / `fs_d.tasks` retirement (migrate Dovecot/Prometheus separately).
- Generic per-job status reporting and `--check` for json-merge. Out of scope;
  see Follow-ups.

## Design

### Core mechanism: carry resolved values in the bin record

The root cause of (1) and (4) is that config scripts depend on ambient
`CONFIG_*` vars that are only resolved late, after scoped import vars expire.
The fix is to **resolve the values at generation time and carry them inside each
bin record**, so they survive into late rendering.

Generalize the `_bin` `vars` mechanism. Today
[`files/_bin:34-36`](/files/_bin) accepts `item.vars` as a **list of names** and
renders `export NAME="${NAME-<current var value>}"` via a late `lookup('vars')`
(which is exactly what breaks). Extend it to also accept a **mapping of concrete
fallback values**:

```jinja
{% for var, fallback in (item.vars if item.vars is mapping else {}).items() %}
export {{ var }}="${{ '{' }}{{ var }}-{{ fallback }}{{ '}' }}"
{% endfor %}
{% for var in (item.vars if item.vars is sequence else []) %}
...existing name-list behavior...
{% endfor %}
```

Then the config subsystem contrib gives each config bin a `vars` mapping with
values resolved at `merge_subsys` render time (scoped vars ARE available there —
`merge_subsys` templates its result before returning,
[`merge_subsys.py:311`](/library/lookup_plugins/merge_subsys.py)):

```yaml
BINS:
  - name: "config-{{ CONFIG_KEY }}.sh"
    src: "../config-{{ CONFIG_MERGE | default('yaml-list') }}.sh"
    basedir: False
    vars:
      CONFIG_KEY: "{{ CONFIG_KEY }}"
      CONFIG_EXT: "{{ CONFIG_EXT }}"
      CONFIG_OUTPUT: "{{ CONFIG_OUTPUT }}"
```

Effect:

- `config-json-merge.sh` is **unchanged** — it already reads `$CONFIG_KEY` /
  `$CONFIG_OUTPUT` as runtime env ([`config-json-merge.sh:15-16`](/files/config-json-merge.sh));
  now each rendered bin exports its own concrete defaults at the top.
- `config-disable.sh` / `config-enable.sh` rebuild name: replace the template
  `{{CONFIG_KEY}}` with the runtime shell var `$CONFIG_KEY` (now exported), so
  no late template render is needed at all.

This is a small, general-purpose `_bin` change that benefits any subsystem
needing per-bin env defaults, not just config.

### MCP output: map MCP_CONF → CONFIG_OUTPUT

In `gen_mcp.tasks`, pass the output the old `mcp-config.sh` used:

```yaml
- import_tasks: gen_config.tasks
  vars:
    CONFIG_KEY: mcp
    CONFIG_MERGE: json-merge
    CONFIG_EXT: json
    CONFIG_OUTPUT: "{{ ETC }}/{{ MCP_CONF | default('opencode.json') }}"
  when: MCP_CLIENT is defined
```

This revives the existing, currently-dead `MCP_CONF` declaration on
[`opencode.src.pb:20`](/opencode.src.pb) (`MCP_CONF: opencode.json`) and
[`amp.opt.pb:16`](/amp.opt.pb) (`MCP_CONF: settings.json`). No playbook changes
needed.

### Disable semantics: keep MCP's override model, drop the generic move

For json-merge jobs, "move the fragment to `-disabled/`" is wrong because the
merger still includes disabled files (disabled-last = highest precedence). The
old MCP behavior — write an `{"enabled": false}` override keeping the same
basename — is the correct json-merge disable.

Two options:

- **(A) Recommended:** let the subsystem suppress generic disable/enable when
  the caller supplies its own. Add an opt-out in the config contrib (e.g.
  `CONFIG_DISABLE: override` or `CONFIG_DISABLE_BINS: false`), set by `gen_mcp`
  since it contributes `mcp-disable.sh`. Generic disable/enable stay available
  for non-override jobs (yaml-list, block-in-file).
- **(B)** drop `mcp-disable.sh` and make generic json-merge disable write
  overrides. More invasive — changes generic semantics shared by other jobs.

Prefer (A): it keeps MCP-specific behavior where it already lives and leaves the
generic path untouched.

### Stale `config.sh` references

Update the rebuild hooks to the generated name:

- [`files/mcp-disable.sh:47`](/files/mcp-disable.sh): `config.sh` → `config-mcp.sh`
- [`files/mcp-install.ts:169-173`](/files/mcp-install.ts): `config.sh` → `config-mcp.sh`

(`config-mcp.sh` is the concrete name from `CONFIG_KEY=mcp`.)

## Concrete change list

1. **`files/_bin`** — `item.vars` accepts a mapping of `{name: fallback}`,
   emitting `export NAME="${NAME-fallback}"` (list form unchanged).
2. **`vars/common.yaml:619-638`** — add `vars:` mapping (CONFIG_KEY/EXT/OUTPUT)
   to the three config BINS records; add a `CONFIG_DISABLE` opt-out.
3. **`files/config-disable.sh`** / **`files/config-enable.sh`** — replace
   `{{CONFIG_KEY}}` rebuild name with `$CONFIG_KEY`; drop the template dep.
4. **`tasks/compfuzor/gen_mcp.tasks:72-78`** — pass `CONFIG_OUTPUT` from
   `MCP_CONF`; set `CONFIG_DISABLE: override` (or chosen opt-out).
5. **`files/mcp-disable.sh:47`**, **`files/mcp-install.ts:169-173`** — point at
   `config-mcp.sh`.
6. (If option A) `gen_config` / config contrib — honor the disable opt-out so
   generic `disable-mcp.sh`/`enable-mcp.sh` are not emitted when MCP supplies
   its own.

## Validation

- Re-run `.test-agent/multi-gen-config/` harness; confirm MCP bins carry
  resolved `CONFIG_KEY=mcp`, `CONFIG_EXT=json`, `CONFIG_OUTPUT=.../opencode.json`.
- Run `opencode.src.pb` with bypass flags through the vars phase; confirm
  `config-mcp.sh` would render with embedded MCP output, and `etc/opencode.json`
  is the target.
- Run a full local install of `opencode.src.pb` and exercise `config-mcp.sh`,
  `mcp-disable.sh`, `mcp-install.ts` end-to-end (disable then enable an MCP,
  confirm rebuild).
- Existing `tests/lookup_plugins/merge_subsys.test.py` stays green; add a test
  for config BINS records carrying a `vars` mapping.

## Follow-ups (explicitly out of scope here)

- `status-config.sh` points at obsolete `bin/config.sh`
  ([`status/status-config.sh:18-23`](/files/status/status-config.sh)) and
  `config-json-merge.sh` lacks the `--check` contract. Both need fixing for
  status to work, but that's a separate status-subsystem pass, not an MCP
  concern.
- `CONFIGS:` collection model for multiple layered outputs.
- `etc_d` as a config source layer; `ETC_D`/`fs_d.tasks` retirement.

## Open questions

1. Disable opt-out naming — `CONFIG_DISABLE: override` vs a boolean
   `CONFIG_DISABLE_BINS: false`? Prefer the descriptive form.
2. Should generic `enable-<key>.sh` learn to remove an override-style disabled
   file (basename collision)? Out of scope for MCP since MCP keeps its own
   `mcp-disable.sh` and no MCP-enable exists today — but worth noting.
3. `_bin` `vars` mapping change is general — worth a separate note that other
   subsystems can use it, or keep it config-only for now?

## Cross-references

- [`tasks/compfuzor/gen_mcp.tasks`](/tasks/compfuzor/gen_mcp.tasks) — MCP
  delegation to gen_config (lines 58-78).
- [`tasks/compfuzor/gen_config.tasks`](/tasks/compfuzor/gen_config.tasks) — the
  generic config artifact synthesis being adopted.
- [`vars/common.yaml`](/vars/common.yaml) (lines 619-638) — the static config
  subsystem contrib being parameterized.
- [`files/config-json-merge.sh`](/files/config-json-merge.sh) — runtime merger,
  unchanged by this design.
- [`library/lookup_plugins/merge_subsys.py`](/library/lookup_plugins/merge_subsys.py)
  (line 311) — where scoped vars resolve into the merged result before return.
- [`opencode.src.pb`](/opencode.src.pb) (lines 11-20) — the driving consumer.
