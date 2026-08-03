---
type: Implementation inventory
title: "merge-star Stage 0 — target contracts and migration inventory"
description: "The acceptance contract and complete legacy-use inventory that must constrain merge-star activation. It identifies every current shape or merge surface, its exact target operation, render-risk cases, and the tests required before live callers can move."
resource: /.design/merge-star/stage0.gpt56t.md
tags: [compfuzor, merge, normalization, migration, stage-0]
status: draft
generated: { by: llm:gpt56t, at: 2026-08-03T00:00:00Z }
sources:
  - id: merge-star-draft3
    resource: /.design/merge-star/draft3.gpt56t.md
    title: fixed pipeline design and delivery stages
  - id: current-merge
    resource: /library/filter_plugins/merge.py
    title: active legacy merge entrypoints
  - id: current-normalizers
    resource: /library/filter_plugins/arrayitize.py
    title: active optional-value list normalizer
  - id: merge-pipeline-scaffold
    resource: /library/filter_plugins/merge_pipeline.py
    title: unactivated fixed-pipeline scaffold
---

# Stage 0: target contracts and migration inventory

## Purpose

Stage 0 makes the target behavior and every migration edge explicit before any
live caller moves. The fixed-pipeline scaffold in
[`merge_pipeline.py`](/library/filter_plugins/merge_pipeline.py) is not
activation: the live `merge_list` / `merge_dict` names still resolve to
[`merge.py`](/library/filter_plugins/merge.py), and all legacy callers remain
in place.

This document is the migration ledger. A later change may move a row only when
its target contract is executable and its render-risk notes have been checked.
Stage 2 may delete a legacy surface only when its ledger rows are all migrated
and the deletion search is clean.

## Stage-0 Gates

| gate | required evidence | current state |
|---|---|---|
| Fixed semantics | Tests cover all five stages, identities, invalid normalized input, tag propagation, removed arguments, profiles, helper layers, and lazy containers. | `merge_pipeline.test.py` covers the pure-value core and lazy boundary. |
| Ansible data boundary | The new core takes a lazy list/dict through its raw-copy boundary without rendering tagged templates. | Shared `template_data.raw_copy_template_data` is covered by activation tests. |
| Caller ledger | Every active legacy call has one named target or an explicit out-of-scope boundary. | This document. |
| Render-risk cases | The `True`-handling change, NVIM's narrow keyed fold, MCP's mapping default, and artifact ordering have target tests or render comparisons. | Not started. |
| Public cutover | Canonical `merge_list` and `merge_dict` replace their legacy filter registrations only after every direct caller has moved. | Deliberately not started. |

The lazy-container gate is a hard stop. The existing merge implementation uses
a raw-copy boundary specifically to avoid evaluating lazy containers and tagged
templates. The target core now uses the same shared boundary before inspecting
Ansible merge inputs.

## Target Contract

| stage | target behavior | executable coverage |
|---|---|---|
| collect | Admits only explicit top-level list/tuple layers. Default skips `None` and Ansible undefined; `false` and `empty` are opt-in names. It never descends into an admitted layer. | `collect` cases in [`merge_pipeline.test.py`](/tests/filter_plugins/merge_pipeline.test.py) |
| normalize: identity | Preserves every value, including `None` and `False`. | Pure-value test |
| normalize: list | `None`, undefined, and `False` become `[]`; sequences become lists; every other scalar, including `True`, becomes a single item. | Pure-value test |
| normalize: mapping | `None`, undefined, and `False` become `{}`; mappings copy; shorthand only accepts a sequence of strings and mappings. | Pure-value test |
| normalize: items | Mapping becomes item records; list/tuple/set pass as item records; `None`, undefined, and `False` become `[]`. | Pure-value test |
| combine | `concat`, `keyed_fold`, `union`, and `replace` receive normalized values only; their identities are `[]`, `[]`, `{}`, and `None`. | Pure-value test |
| refine | Equality dedupe supports unhashable values; keyed dedupe keeps first position and last record; implications are transitive and reject graph cycles; canonicalization has explicit unknown policy. | Pure-value test |
| preset | One normalizer, one combine, ordered fixed refines, and a declared result kind. A configuration may override only declared options. | Pure-value test |
| fields | `{"preset": ...}` is a leaf and `{"fields": ...}` recurses. No aggregate, payload-path, `into`, or `single` preparation grammar remains. | Pure-value test |
| helpers | The caller builds default/base/bypass/author layers; only `helpers: False` is nuclear before the pipeline. `base_helpers: False` is one skipped layer. | Pure-value layer test; caller integration pending |

### Intentional semantic changes

These are target contracts, not implementation accidents. Every caller that
could receive these values needs an explicit declaration or render test before
migration.

| input | legacy `arrayitize` | `normalize(to='list')` | migration consequence |
|---|---|---|---|
| `None` / undefined | `[]` | `[]` | compatible |
| `False` | `[]` | `[]` | compatible |
| `True` | `[]` | `[True]` | blocking audit: `True` is data in the target vocabulary |
| `0` | `[0]` | `[0]` | compatible |
| mapping | `[mapping]` | `[mapping]` | compatible |

| input | legacy `listify` | target | migration consequence |
|---|---|---|---|
| mapping | `[{key, value}]` | `normalize(to='items')` | retain mapping-to-record conversion explicitly |
| `False` / `0` / empty mapping | `[]` | `normalize(to='list')` is `[]` / `[0]` / `[{}]` | target choice must match the field's domain |
| string/list/tuple | list-shaped value | `normalize(to='list')` | compatible for declared list inputs |

The active merge has two other material differences that require direct tests:

| legacy behavior | target behavior | affected migration |
|---|---|---|
| `append_unique` dedupes by `str(value)` | `dedupe` uses Python equality | Every `append_unique` caller must establish the expected equality domain. |
| `mergeKeyed` in `vars_nvim` concatenates only `generated` | `bins_generated` concatenates `early`, `generated`, and `run_all` | NVIM must use configured `merge_keyed`, not `bins_generated`. |
| `mergeKeyed` in `vars_mcp` receives `BINS | default({})`, which legacy code silently ignores when it is a mapping | Target must use `BINS | default([])` and establish the intended list-only contract. |

## Inventory

### Direct merge calls

| source | target | notes |
|---|---|---|
| [`gen_zim.tasks:76,93`](/tasks/compfuzor/gen_zim.tasks) | `merge_list(preset='bins_generated')` | Syntax-only preset keyword migration. |
| [`gen_bins.tasks:15`](/tasks/compfuzor/gen_bins.tasks) | `merge_list(preset='bins_generated')` | Check compositor output stays tagged and ordered. |
| [`gen_get_urls.tasks:4`](/tasks/compfuzor/gen_get_urls.tasks) | `merge_list(preset='bins_generated')` | Syntax-only preset keyword migration. |
| [`gen_status.tasks:18`](/tasks/compfuzor/gen_status.tasks) | `merge_list(preset='bins_generated')` | Syntax-only preset keyword migration. |
| [`gen_python.tasks:12`](/tasks/compfuzor/gen_python.tasks) | `merge_list(preset='bins_generated')` | Syntax-only preset keyword migration. |
| [`gen_tool_versions.tasks:9,10,22,23`](/tasks/compfuzor/gen_tool_versions.tasks) | `merge_list(preset='append')` | Preserve current-first vs generated-first layer ordering exactly. |
| [`gen_tool_versions.tasks:24`](/tasks/compfuzor/gen_tool_versions.tasks) | `merge_list(preset='bins_generated')` | Syntax-only preset keyword migration. |
| [`gen_kernel.tasks:42`](/tasks/compfuzor/gen_kernel.tasks) | `merge_list(preset='append')` | Preserve six-layer source order. |
| [`gen_kernel.tasks:48`](/tasks/compfuzor/gen_kernel.tasks) | `merge_list(preset='bins_generated')` | Render comparison for keyed bin ordering and generated fields. |
| [`gen_kernel.tasks:50,51`](/tasks/compfuzor/gen_kernel.tasks) | `merge_list(preset='append_unique')` | Establish Python-equality package and env-list expectations. |
| [`gen_zim.tasks:77,94`](/tasks/compfuzor/gen_zim.tasks) | `[_zim_host_env, ENV \| default({})] \| merge_dict(preset='overlay', skip_layers=['none', 'undefined', 'false', 'empty'])` | Retains legacy `skip='all'` and current ENV precedence. |
| [`gen_status.tasks:19`](/tasks/compfuzor/gen_status.tasks) | `[_status_contrib.ENV, ENV] \| merge_dict(preset='overlay', skip_layers=['none', 'undefined', 'false', 'empty'])` | Retains legacy `skip='all'` and current ENV precedence. |
| [`gen_nodejs.tasks:15-21`](/tasks/compfuzor/gen_nodejs.tasks) | `[ENV, conditional build/prune mappings...] \| merge_dict(preset='overlay')` | The current variadic merge becomes an explicit ordered layer list. |
| [`gen_tool_versions.tasks:4,5,30`](/tasks/compfuzor/gen_tool_versions.tasks) | `[value] \| merge_dict(preset='tool_versions_overlay')` and `[_tool_versions, _mise_versions] \| merge_dict(preset='tool_versions_overlay')` | Remove redundant `single=true`; check shorthand mapping output. |
| [`gen_kernel.tasks:49`](/tasks/compfuzor/gen_kernel.tasks) | `[modprobe.ENV, sysctl.ENV, sysfs.ENV, params.ENV, bls.ENV, ENV] \| merge_dict(preset='overlay', skip_layers=['none', 'undefined', 'false', 'empty'])` | Preserve five incoming layers followed by current ENV. |
| [`vars_nvim.tasks:4`](/tasks/compfuzor/vars_nvim.tasks) | `[enhancedBins, bins] \| merge_list(preset={'name': 'merge_keyed', 'key': 'name', 'concat_fields': ['generated']})` | Do not substitute `bins_generated`: this caller deliberately has a narrower concat contract. |
| [`vars_mcp.tasks:48`](/tasks/compfuzor/vars_mcp.tasks) | `[[config, disable, install], BINS \| default([])] \| merge_list(preset={'name': 'merge_keyed'})` | Decide and test records' key field. The current `{}` default is silently discarded by the legacy shim. |

### Artifact lookup policy

[`merge_subsys.py`](/library/lookup_plugins/merge_subsys.py) is the public
artifact merge boundary used by 35 task sites. Its target registry owns only
artifact name, value preset, and layer order:

| artifacts | target preset | target order |
|---|---|---|
| `BINS` | `bins_generated` | current-first |
| `ETC_FILES`, `LINKS`, `ETC_DIRS` | `append` | current-first |
| `PKGS`, `ENV_LIST` | `append_unique` | current-first |
| `ENV`, `ENV_PRIO` | `overlay` | incoming-first when current wins |
| `TOOL_VERSIONS` | `tool_versions_overlay` | incoming-first when current wins |

Default lookup calls remain structurally `lookup('merge_subsys', id=..., contrib=...)`.
The three strategy overrides must migrate from `strategy='append'` to
`preset='append'`:

- [`gen_desktop.tasks:5`](/tasks/compfuzor/gen_desktop.tasks)
- [`gen_cmake.tasks:5`](/tasks/compfuzor/gen_cmake.tasks)
- [`gen_rust.tasks:6`](/tasks/compfuzor/gen_rust.tasks)

The 32 remaining default calls are in:

- [`gen_make.tasks:4`](/tasks/compfuzor/gen_make.tasks)
- [`gen_readme.tasks:4`](/tasks/compfuzor/gen_readme.tasks)
- [`gen_bazel.tasks:4-5`](/tasks/compfuzor/gen_bazel.tasks)
- [`gen_patches.tasks:4`](/tasks/compfuzor/gen_patches.tasks)
- [`gen_config.tasks:4-6`](/tasks/compfuzor/gen_config.tasks)
- [`gen_desktop.tasks:4`](/tasks/compfuzor/gen_desktop.tasks)
- [`gen_bun.tasks:4-6`](/tasks/compfuzor/gen_bun.tasks)
- [`gen_npm.tasks:4-7`](/tasks/compfuzor/gen_npm.tasks)
- [`gen_cmake.tasks:4,6-7`](/tasks/compfuzor/gen_cmake.tasks)
- [`gen_nodejs.tasks:7-9`](/tasks/compfuzor/gen_nodejs.tasks)
- [`gen_rust.tasks:4-5,7`](/tasks/compfuzor/gen_rust.tasks)
- [`gen_go.tasks:4-6`](/tasks/compfuzor/gen_go.tasks)
- [`gen_python.tasks:4-7`](/tasks/compfuzor/gen_python.tasks)

### Shape conversion

| source | target | notes |
|---|---|---|
| [`dictify.py`](/library/filter_plugins/dictify.py) and its only runtime user [`merge.py:405`](/library/filter_plugins/merge.py) | `normalize(to='mapping', shorthand=true)` within `tool_versions_overlay` | Delete only after `merge_subsys` and direct tool-version callers use the target preset. |
| [`links.tasks:27`](/tasks/compfuzor/links.tasks) | `normalize(to='items')` | Existing mapping inputs emit `{key, value}` and task fallback fields already accept both forms. |
| [`vars_base.tasks:146`](/tasks/compfuzor/vars_base.tasks) | `normalize(to='items', key_name='dest', value_name='src')` | Mapping-only guarded conversion. |
| [`repo_git.tasks:24`](/tasks/compfuzor/repo_git.tasks) | `normalize(to='items')` | Mapping branch only. |
| [`gen_kernel.tasks:7`](/tasks/compfuzor/gen_kernel.tasks) | `normalize(to='items')` | Mapping-only guarded conversion. |
| [`vars/common.yaml:988`](/vars/common.yaml) | `normalize(to='list')` | `MAKE_TARGET` must be declared a string/list domain; `0` changes from empty to data. |
| [`k3s.srv.pb:186`](/k3s.srv.pb) | `[extraDomains, _cluster_hosts, extraIpv4Domains] \| merge_list(preset='append')` | Preserve list order before `unique`. |
| [`vars_systemd_unit.tasks:213`](/tasks/compfuzor/vars_systemd_unit.tasks), [`vars_nvim.tasks:3`](/tasks/compfuzor/vars_nvim.tasks), [`vars_mcp.tasks:3,15,49`](/tasks/compfuzor/vars_mcp.tasks) | `[left, right] \| merge_list(preset='append')` | Preserve the legacy left-to-right concatenation order. |
| [`bin_composers.py:23,81,94`](/library/filter_plugins/bin_composers.py) | `normalize(to='list')` plus explicit caller-side `True` handling for `scope` | `scope: true` is currently no contribution but would become a literal `"True"` scope. No local normalizer survives. |
| [`pkgs.py:57-64`](/library/lookup_plugins/pkgs.py) | Reuse `normalize(to='list')` only after package lookup declares its `False` behavior | It is another local optional-list helper, but it currently keeps `False` as data and later discards it by type. |

All 79 direct runtime `arrayitize` calls target `normalize(to='list')`, but
they cannot be bulk-rewritten until their `True` behavior is declared:

| file | exact lines |
|---|---|
| [`files/systemd.service`](/files/systemd.service) | 2, 10, 90, 101, 231, 246 |
| [`files/systemd.mount`](/files/systemd.mount) | 2, 10, 19, 31, 41 |
| [`files/systemd.netdev`](/files/systemd.netdev) | 11 |
| [`files/_bin`](/files/_bin) | 40-46, 54 |
| [`files/_env`](/files/_env) | 21 |
| [`files/_content`](/files/_content) | 1 |
| [`files/debootstrap/_pkgs`](/files/debootstrap/_pkgs) | 3, 8, 10 |
| [`files/samba/smb.conf`](/files/samba/smb.conf) | 7, 25 |
| [`tasks/compfuzor.includes`](/tasks/compfuzor.includes) | 135, 136 |
| [`vars/common.yaml`](/vars/common.yaml) | 173, 182, 220, 228, 247, 273, 312, 321, 356, 382, 464, 497, 500, 531, 590, 731, 732, 744, 756-759, 764, 789, 792, 797, 806, 814, 829, 842, 887, 892, 895, 943, 948, 978, 993 |
| [`vars_systemd_env.tasks`](/tasks/compfuzor/vars_systemd_env.tasks) | 74, 75 |
| [`sub_get_urls.tasks`](/tasks/compfuzor/sub_get_urls.tasks) | 7 |
| [`repo_go.tasks`](/tasks/compfuzor/repo_go.tasks) | 5 |
| [`pkgs.tasks`](/tasks/compfuzor/pkgs.tasks) | 7 |
| [`fs_hierarchy.tasks`](/tasks/compfuzor/fs_hierarchy.tasks) | 93 |
| [`gen_python.tasks`](/tasks/compfuzor/gen_python.tasks) | 13 |
| [`fs_env.tasks`](/tasks/compfuzor/fs_env.tasks) | 30, 57, 126, 153 |
| [`iface.tasks`](/tasks/compfuzor/iface.tasks) | 5, 11 |

### Helper and field-profile retirement

| source | target | notes |
|---|---|---|
| [`helpers.py`](/library/filter_plugins/helpers.py) | Caller-side nuclear branch plus `merge_list(preset='helpers', skip_layers=['none', 'undefined', 'false'])` | Move bypass-layer construction to [`files/_bin`](/files/_bin); delete the legacy merge call and `no_header` branch. |
| [`pw-surround.etc.pb:38,46`](/pw-surround.etc.pb) and [`vars_systemd_unit.tasks:208`](/tasks/compfuzor/vars_systemd_unit.tasks) | `helpers: false` | The only permitted nuclear spelling. |
| [`merge_strategy.py`](/library/filter_plugins/merge_strategy.py) | `merge_fields(records, profile=...)` | No live task caller remains after `mergeKeyed` migrates. Remove aggregate, payload path, `into`, and `single` grammar rather than carrying a shim. |
| [`mergeKeyed.py`](/library/filter_plugins/mergeKeyed.py) | Configured `merge_keyed` preset | Delete after NVIM and MCP migrations above. |
| [`merge_list_subsys` / `merge_dict_subsys`](/library/filter_plugins/merge.py) | No replacement until liveness check | They overlap `merge_subsys`; remove if no external consumer exists. |
| [`subsys_publish` / `_deep_merge_dicts`](/library/filter_plugins/merge.py) | Explicit subsystem-publication boundary or deletion | It is not part of the value pipeline. |

### Published documentation and legacy tests

| source | target | notes |
|---|---|---|
| [`README.md`](/README.md) | Replace the legacy merger sections and examples with the fixed API, then add the pipeline contract suite to the test command list. | Current examples use positional strategies and describe retired filters. |
| [`library/README.md`](/library/README.md) and [`library/filter_plugins/INDEX.md`](/library/filter_plugins/INDEX.md) | Make `normalize`, `merge_list`, `merge_dict`, and `merge_fields` the authoritative filter catalogue. | Remove the current side-by-side comparison of overlapping helpers once they are deleted. |
| [`doc/arch.md`](/doc/arch.md), [`doc/subsys.md`](/doc/subsys.md), and [`doc/bins.md`](/doc/bins.md) | Replace `merge_with_strategy`, `dictify`, `arrayitize`, `mergeKeyed`, and `no_header` descriptions with presets, profiles, and `helpers: false`. | These documents describe live architecture rather than historical behavior. |
| [`doc/prefix.codex.md`](/doc/prefix.codex.md) | Update the live `arrayitize` expression when its owning task migrates. | It is a migration-oriented document but still presents current code. |
| [`doc/prefix-transcript.md`](/doc/prefix-transcript.md) | Retain literal historical excerpts, but label them historical rather than current guidance. | Do not rewrite transcript quotations into false history. |
| [`dictify.test.py`](/tests/filter_plugins/dictify.test.py), [`merge.test.py`](/tests/filter_plugins/merge.test.py), [`merge_strategy.test.py`](/tests/filter_plugins/merge_strategy.test.py), and [`mergeKeyed.test.py`](/tests/filter_plugins/mergeKeyed.test.py) | Replace with target tests, then delete alongside their retired module. | Test names must not preserve compatibility forms after deletion. |
| [`helpers.test.py`](/tests/filter_plugins/helpers.test.py) | Keep helper behavior coverage but replace the `no_header` case with rejection/absence coverage. | Nuclear behavior remains caller-side. |

## Required Tests Before Cutover

The pure pipeline contract is in
[`merge_pipeline.test.py`](/tests/filter_plugins/merge_pipeline.test.py). The
following acceptance tests are still required before the legacy filter names
may point at the new core:

1. Tagged template strings stay tagged through keyed string concatenation in an
   Ansible templating invocation, not only a direct Python call.
2. The helper caller constructs the bypass layer, suppresses `base_helpers:
   false`, returns `[]` for `helpers: false`, and rejects `no_header`.
3. `merge_subsys` derives BINS, list, ENV, and tool-version results exclusively
   from `ARTIFACT_DEFAULTS` preset/order metadata, including both precedence
   orders.
4. NVIM's generated field concatenation remains narrow, while bins-generated
   still joins `early`, `generated`, and `run_all`.
5. MCP's BINS contribution is a valid keyed-record list; if it is not, repair
   the record contract before migration instead of preserving the current silent
   drop.
6. Every `arrayitize` group above has a declared response to `True`, with
   rendered output tests for templates and playbooks where it is a valid input.

## Deletion Checks

After migration, run scoped repository searches (excluding this historical
design directory) for these retired runtime names:

```text
arrayitize
dictify
listify
concat(
mergeKeyed
merge_with_strategy
dict2items
no_header
strategy=
single=
skip=
dict_overlay
env_overlay
```

An empty search is necessary but not sufficient: the acceptance tests above and
the normal playbook test suite must pass before deleting the old modules.
