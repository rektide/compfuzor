---
type: Audit
title: "def/omit leak audit — enum-like selection vars and sentinel flow"
description: Classification of every default(...omit...) site plus enum-like selection vars, after the SYSTEMD_SCOPE shadow bug (2f4b32cd) and the def filter's skip_omit/enum kwargs (b93d66e4).
resource: /design/def-omit-audit/audit.glmmax.md
tags: [ansible, systemd, def-filter, omit]
status: stable
generated: { by: model:glm-max, at: 2026-08-20T17:10:00Z }
verified: { by: model:glm-max, at: 2026-08-20T17:10:00Z }
stale_after: 2027-02-20
sources:
  - id: scope-shadow-bug
    resource: https://github.com/rektide/compfuzor/commit/2f4b32cd
    title: "systemd unit gen: unshadow SYSTEMD_SCOPE in unit render loop"
  - id: def-filter-upgrade
    resource: /library/filter_plugins/def.py
    title: "def filter — skip_omit and enum kwargs (b93d66e4)"
    last_modified: 2026-08-19
  - id: canonical-form
    resource: /tasks/compfuzor/vars_systemd_unit.tasks
    title: "Canonical skip_omit/falsy/enum usage sites"
---

# def/omit leak audit

## What this is

Follow-up sweep after the `SYSTEMD_SCOPE` shadow bug: a task-level var of the
same name shadowed the playbook value, and because ansible's `omit` sentinel
counts as *defined* (and is *truthy* — `bool(Omit) is True`), neither
`X|default(Y)` nor `X|default(Y, true)` can fall back past it; the sentinel
renders as `''` in string context and silently misses every `== 'user'`
comparison. This audit enumerates every place the tree still plays with
`default(...omit...)` or enum-like selection vars and classifies each.

## Empirical ground rules established while auditing

Three probe results (playbooks in `/home/rektide/tmp-opencode/def-audit/`,
not committed) that shaped the classifications:

1. **`set_fact` drops omit-valued keys.** A fact whose value is entirely the
   sentinel is *omitted from the fact set*, not stored ("No key/value pairs
   provided" when every key is omitted). So `X: "{{X|default(omit)}}"` is the
   "conditionally-set fact" idiom — the sentinel never reaches later tasks.
2. **Container finalization strips sentinel-valued dict keys at var
   consumption.** `json.headers: "{{ MCP_HEADERS|default(omit) }}"` renders
   `mcp.json` *without* the `headers` key (verified: deepwiki render). A
   sentinel that reaches `to_nice_json` inside a single template expression
   *does* crash (`'_OmitType' is not JSON serializable`) — the working idiom
   relies on the dict crossing a var boundary first.
3. **`vars_files` outrank play `vars`.** Probing overrides must use `-e`.
   (Also the reason enum tests below pass `-e`.)

## Rule of thumb applied

- **MUST-FLOW** when the sentinel's *job* is to strip something (module
  param, dict key, fact key) or when the var crosses into the subsystem
  pipeline where finalization drops it. Also when authored falsy values are
  meaningful (`validate_certs: false`, `SYSTEMD_INSTALL: false`).
- **LEAK-RISK** when a selection var feeds `==`/`in` branches and an `''`
  or sentinel leak (or a typo) would silently pick the wrong branch. Fix
  with the full `| def(FALLBACK, skip_omit=True, falsy=True, enum=[...])`
  form — but only where falsy values are *not* authored (scope vars).
- **LOUD-FAIL** when the var is guaranteed defined (var-file default) so
  leak is impossible, but a typo would silently disable/misdirect a branch.
  Fix with `enum=` only; no falsy coalescing when falsy values are authored.

## Classification — the 25 `default(...omit...)` sites

All 25 are **MUST-FLOW**; none needed changing. Grouped:

| Sites | Idiom | Why it must flow |
|---|---|---|
| `vars/common.yaml:228` (`GO_BIN`), `:329` (`NPM_PACKAGE`), `:885` (`CMAKE_GENERATOR`), `:887` (`CMAKE_INSTALL_BIN`) | conditionally-present env/JSON entries in subsystem contribs | pipeline drops/`''`-renders them; consumers guard (`[ -n ... ]`) |
| `tasks/compfuzor/vars_systemd_unit.tasks:5` (`SYSTEMD_USER`), `:8` (`ETC_DIRS`), `:22` (`serviceExec`), `:23` (`serviceNameDefault`); `vars_base.tasks:78` (`SUBINSTANCE`); `vars_src.tasks:10` (`SRC`); `gen_npm.tasks:8` (`NPM_PACKAGE_BIN` lookup default) | conditionally-set facts | `set_fact` drops omit-valued keys; same-task consumers see the *pre-fact* (possibly undefined) value |
| `fs_repo.tasks:7,14`, `fs_pkgs.tasks:8,9`, `fs_get_urls.tasks:7,8,19,20` (`owner`/`group`), `repo_git.tasks:128` (`depth`), `:130` (`update`), `fs_base.tasks:48` / `fs_hierarchy.tasks:97` (`state`) | module params | the canonical omit purpose: drop the param so the module default applies |
| `vars_hierarchy.tasks:23` | commented out | dead code |

Adjacent same-idiom sites (not in the 25): `gen_mcp.tasks:20`
(`headers`) and `:52` (`{{ omit }}` for `environment`) — conditionally-present
JSON keys, empirically verified working (deepwiki `mcp.json`).

## Classification — enum-like selection sites

| Site | Class | Action |
|---|---|---|
| `tasks/systemd.unit.includes:47` `_scope` | fixed pre-audit (b93d66e4) | none |
| `tasks/compfuzor/vars_systemd_unit.tasks:58` `_scope` | fixed pre-audit | none |
| `tasks/compfuzor/vars_systemd_unit.tasks:213` dropin `scope` | fixed pre-audit | none |
| `tasks/systemd.unit.includes:27` `_user_suffix` raw `SYSTEMD_SCOPE == 'user'` beside the fixed `_scope` | **LEAK-RISK** | **fixed**: use `_scope` |
| `vars/systemd.yaml` `SYSTEMD_*_*_INSTALL` gates (8) + `vars_systemd_unit.tasks:31`/`:286` `== 'separate'` — `SYSTEMD_INSTALL` typo silently installs nothing / silently drops dual-render | **LOUD-FAIL** | **fixed**: `SYSTEMD_INSTALL_VALID` with `enum=['system','user','both','separate','none',true,false]`; `true`/`false` are authored values so no falsy coalescing |
| `vars/systemd.yaml` `SYSTEMD_INSTALLS_DEFAULT.WantedBy` raw `SYSTEMD_SCOPE == 'system'` — typo silently renders `default.target` in system units | **LOUD-FAIL** | **fixed**: `\|def('system', enum=['system','user'])` |
| `vars/systemd.yaml` `SYSTEMD_SERVICE_SUFFIX` raw scope compare | **LOUD-FAIL** | **fixed** (same form; var currently has no consumers) |
| `vars/systemd.yaml:2` `SYSTEMD_OPTS_AND_SCOPE`, `tasks/systemd.unit.includes:85` `systemctl --{{ SYSTEMD_SCOPE }}` | loud already | left: bad scope → invalid systemctl operation → runtime failure |
| `vars/systemd.yaml:5,6,42` lookups keyed on `SYSTEMD_SCOPE|upper` | loud already | left: miss → undefined-var lookup error |
| `_dir_map` (`network`/`nspawn`/`system`), `vars_systemd_unit.tasks:288-293` | internal | left: derived from `SYSTEMD_TYPE_CONFIG`, not user-authored |
| link-plan `scope` (`LINKS`, artifact `link:`/`links:` annotations) | loud already | left: `artifact_links.py` `_SCOPES` validates loudly |
| `item.validate_certs | default(true)` (`fs_get_urls.tasks`) | MUST-FLOW | left: authored `false` is meaningful; plain `default` fires only on undefined |

## Shadow sweep

`rg` for task-level `vars:` uppercase redefinitions found no remaining
same-name shadows. The `SYSTEMD_SCOPE` shadow from 2f4b32cd was the only
instance. Things that look like shadows but are not:

- `tasks/compfuzor/systemd.tasks:5,16` — `PREFIX_DIR` save/mutate/restore
  via sequential `set_fact`s (args template against the pre-fact value).
- `tasks/compfuzor/vars_repo.tasks:25`, `gen_links.tasks:32-35` — `ENV`/`BINS`
  accumulator `set_fact`s.
- `tasks/compfuzor/compile_artifacts.tasks:7-43` — a mapping built *for* the
  filter, not vars exposed to the task.
- `tasks/apt.srclist.install.tasks:5` — `APT_SRC: 1` sets a flag consumed by
  the included file; shadows nothing it falls back on.

## Verification

- `python3 tests/filter_plugins/def.test.py` — 42 passing (filter untouched).
- `watchman.srv.pb` (scope/install = user): deleted unit, re-rendered with
  only `SYSTEMD_THUNK_BYPASS` — byte-identical, `ExecStart` keeps all three
  `%h/...` paths.
- `rclone.srv.pb` (separate): rendered with edits, with edits reverted
  (parent-rev files), diffed — byte-identical; dual `-user` files regenerate.
  (Blank-line drift vs stale on-disk units predates this audit — same drift
  reproduces pre-edit.)
- `tmux-tracker.src.pb` (`SYSTEMD_INSTALL: false`): full unit-gen phase clean;
  only failure is environmental (missing `~/archive` checkout).
- `deepwiki.opt.pb`: stable, `mcp.json` identical.
- Typo probes (with `-e`, since `vars_files` outrank play vars):
  `SYSTEMD_INSTALL=seperate` → `def: value 'seperate' is not one of enum [...]`;
  `SYSTEMD_SCOPE=usr` → `def: value 'usr' is not one of enum ['system', 'user']`;
  legit `user`/`false`/`separate`/user-scope `default.target` all pass.

## Known behavior change

`-e SYSTEMD_INSTALL=false` (string `'false'` from the CLI) now fails the
enum. Previously the string silently missed every gate membership, which
coincidentally matched the documented `false`=none intent. YAML-authored
`false` (all in-tree playbooks) still passes. The crash message lists the
legal values, which is the point of the enum.

## Follow-up candidates deliberately not changed

1. **`gen_mcp.tasks` list-form `MCP_COMMAND` crash (live bug, different
   class).** `github-mcp.src.pb` and `jj-mcp-server.src.pb` fail today:
   `'mcp_command_with_args' is undefined` — the nested template survives
   `merge_list` and resolves after the task's vars leave scope. Same class
   as the one `gen_tool_versions.tasks:23-25` documents; fix is
   `resolve=True` or pre-rendering `mcp_command_with_args`, but that
   interacts with the omit-dropping behavior and deserves its own change.
2. `tasks/systemd.unit.includes` is a dormant path (its include in
   `compfuzor.includes:207-212` is commented out); the `_user_suffix` fix
   keeps it consistent but nothing exercises it in-tree.
3. `SYSTEMD_OPTS_AND_SCOPE`/`systemctl --{{SYSTEMD_SCOPE}}` could route
   through a validated scope for symmetry, but they already fail loudly.
4. `vars_hierarchy.tasks:23` commented `hostvars[...]|default(vars[name]|default(omit))`
   — dead; remove with the next vars_hierarchy pass.
5. `SUBINSTANCE`'s sentinel-as-fact shape is safe only because same-task
   consumers see the pre-fact value; a future consumer doing
   `SUBINSTANCE is deftruthy` *after* the fact would see truthy-''.
   Currently no such consumer exists.

## References

- [`/library/filter_plugins/def.py`](/library/filter_plugins/def.py) — the filter.
- [`/tests/filter_plugins/def.test.py`](/tests/filter_plugins/def.test.py) — standalone test script (`python3 tests/filter_plugins/def.test.py`).
- [`/tasks/compfuzor/vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks), [`/tasks/systemd.unit.includes`](/tasks/systemd.unit.includes), [`/vars/systemd.yaml`](/vars/systemd.yaml) — canonical usage and the sites fixed here.
- [`/library/filter_plugins/artifact_links.py`](/library/filter_plugins/artifact_links.py) — the Python-side reference for loud scope validation.
