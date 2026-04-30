# Compfuzor Toolkit

Filters and helpers built during the subsystem-model refactor. Each lives in
[`library/filter_plugins/`](library/filter_plugins/) and is tested in a
co-located `<name>.test.py`.

## Filter plugins

### `merge_with_strategy` — [`merge_strategy.py`](library/filter_plugins/merge_strategy.py)

Strategy-driven record merger. The core synthesis engine.

```yaml
# inline strategy map
records | merge_with_strategy(
  {"BINS": "append", "ENV": "dict_overlay"},
  payload_path="contrib"
)

# named profile
records | merge_with_strategy("subsystem_contrib", payload_path="contrib")
```

**String strategies:** `append`, `append_unique`, `dict_overlay`, `replace`

**Operation strategies** (dict with `op` key):

| op | purpose |
|---|---|
| `merge_keyed` | merge lists of dicts by key, with `concat_fields` for string/list field joining |
| `append_unique_by` | append + deduplicate by a dict key (last wins, first-seen position) |

**Nested strategies:** any dict without `op` is recursed as a sub-field map.

**Named profiles:**

| Profile | Fields |
|---|---|
| `subsystem_contrib` | ETC_FILES append, BINS append, ENV dict_overlay, ENV_LIST append_unique, PKGS append_unique |
| `subsystem_artifacts` | ETC_FILES append, LINKS append |

`payload_path` walks a dot-separated path (e.g. `"contrib.artifacts"`) to
extract the working payload from each record.

**Used in:** [`subsystem_rollup.py`](library/filter_plugins/subsystem_rollup.py),
[`mergeKeyed.py`](library/filter_plugins/mergeKeyed.py) (compat shim),
[`fn_kernel.tasks`](tasks/compfuzor/fn_kernel.tasks)

---

### `subsystem_rollup` — [`subsystem_rollup.py`](library/filter_plugins/subsystem_rollup.py)

Thin wrapper over `merge_with_strategy` with the `"subsystem_contrib"` profile
and `payload_path="contrib"`.

```yaml
[modprobe_state, sysctl_state, sysfs_state] | subsystem_rollup({}, false)
```

**Used in:** [`fn_kernel.tasks`](tasks/compfuzor/fn_kernel.tasks)

---

### `subsystem_record` — [`subsystem_record.py`](library/filter_plugins/subsystem_record.py)

Builds a subsystem runtime record with computed status/active/reasons from
context vars or explicit overrides. Attaches `spec` and `contrib` only when
appropriate.

```yaml
"kernel_sysctl" | subsystem_record(
  sysctl_requested, sysctl_bypassed, valid, errors, sysctl_spec, sysctl_contrib
)
```

**Used in:** [`fn_kernel.tasks`](tasks/compfuzor/fn_kernel.tasks)

---

### `build_install_bins` — [`subsystem_record.py`](library/filter_plugins/subsystem_record.py)

Returns standard `build_bins` / `install_bins` entries for a stem name.

```yaml
"sysctl" | build_install_bins
# => {build_bins: [{name: "build-sysctl.sh", ...}], install_bins: [{name: "install-sysctl.sh", ...}]}
```

**Used in:** [`fn_kernel.tasks`](tasks/compfuzor/fn_kernel.tasks)

---

### `subsystem_bypassed` / `subsystem_bypass_vars` — [`subsystem_bypass.py`](library/filter_plugins/subsystem_bypass.py)

Resolves effective bypass state from subsystem + domain naming rules.
Supports auto-defaults, explicit replacement, and supplement modes.

```yaml
"kernel_sysctl" | subsystem_bypassed(true, "kernel")
```

**Used in:** [`fn_kernel.tasks`](tasks/compfuzor/fn_kernel.tasks)

---

### `owner_group_fields` — [`subsystem_bypass.py`](library/filter_plugins/subsystem_bypass.py)

Row-first owner/group resolution with context fallback.

```yaml
row | owner_group_fields
```

**Used in:** [`fn_get_urls.tasks`](tasks/compfuzor/fn_get_urls.tasks)

---

### `concat2` — [`concat2.py`](library/filter_plugins/concat2.py)

Concatenation that tolerates `undefined`/`None` on either side. Optional
`unique=True` for order-preserving dedup.

```yaml
ETC_FILES | concat2(new_items)
ENV_LIST | concat2(new_keys, unique=True)
```

**Used in:** [`gen_kernel.tasks`](tasks/compfuzor/gen_kernel.tasks),
[`gen_tool_versions.tasks`](tasks/compfuzor/gen_tool_versions.tasks)

---

### `mergeKeyed` — [`mergeKeyed.py`](library/filter_plugins/mergeKeyed.py)

Compatibility shim over `merge_with_strategy`'s `merge_keyed` operation.
Merges two lists of dicts by key, with optional `concat_fields`.

```yaml
enhancedBins | mergeKeyed(bins, key="name", concat_fields=["generated"])
```

**Used in:** [`gen_kernel.tasks`](tasks/compfuzor/gen_kernel.tasks),
[`gen_get_urls.tasks`](tasks/compfuzor/gen_get_urls.tasks),
[`vars_python.tasks`](tasks/compfuzor/vars_python.tasks),
[`vars_go.tasks`](tasks/compfuzor/vars_go.tasks)

## Architecture contract

See [`doc/arch.md`](doc/arch.md) for the full subsystem model, phase lifecycle,
prefix conventions (`fn_`/`gen_`/`fs_`), and worked examples.

## Task file prefixes

| Prefix | Phase | Purpose |
|---|---|---|
| `fn_*` | compile.transform | Normalize input, build subsystem contracts and state |
| `gen_*` | compile.synthesis | Aggregate contribs into shared globals |
| `fs_*` | fs-apply | Materialize files, links, downloads |

## Migrated task files

| File | Former name | Status |
|---|---|---|
| [`fn_get_urls.tasks`](tasks/compfuzor/fn_get_urls.tasks) | `vars_get_urls.tasks` | Complete |
| [`gen_get_urls.tasks`](tasks/compfuzor/gen_get_urls.tasks) | — | Complete |
| [`fn_kernel.tasks`](tasks/compfuzor/fn_kernel.tasks) | `vars_kernel.tasks` | Complete |
| [`gen_kernel.tasks`](tasks/compfuzor/gen_kernel.tasks) | — | Complete |
| [`gen_tool_versions.tasks`](tasks/compfuzor/gen_tool_versions.tasks) | `vars_tool_versions.tasks` | Complete |

## Test suite

```sh
python tests/filter_plugins/merge_strategy.test.py   # 36 tests
python tests/filter_plugins/mergeKeyed.test.py       # 11 tests
python tests/filter_plugins/subsystem_rollup.test.py  #  9 tests
python tests/filter_plugins/subsystem_bypass.test.py  # 18 tests
python tests/filter_plugins/subsystem_record.test.py  # 27 tests
python tests/filter_plugins/concat2.test.py           # 14 tests
python tests/filter_plugins/get.test.py                #  9 tests
python tests/filter_plugins/cmdline.test.py            # 12 tests
python tests/lookup_plugins/subsys.test.py             #  8 tests
```
