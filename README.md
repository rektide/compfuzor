# Compfuzor Toolkit

Compile-and-apply system for host configuration. Users declare intent in
playbooks (`.pb`); compfuzor compiles that intent into subsystem state,
synthesizes shared artifacts, then applies the result to repositories,
filesystems, services, packages, and kernel state.

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

**Named profiles:**

| Profile | Fields |
|---|---|
| `subsystem_contrib` | ETC_FILES append, BINS append, ENV dict_overlay, ENV_LIST append_unique, PKGS append_unique |
| `subsystem_artifacts` | ETC_FILES append, LINKS append |

---

### `merge_list` / `merge_dict` — [`merge.py`](library/filter_plugins/merge.py)

Direct list and dict merging without wrapper records.

```yaml
# list merge with named strategy
BINS: "{{ [existing, incoming] | merge_list('bins_generated') }}"

# dict merge
ENV: "{{ [defaults, overrides] | merge_dict('env_overlay') }}"
```

**List strategies:** `append`, `append_unique`, plus operation dicts (`merge_keyed`, `append_unique_by`)

**Dict strategies:** `overlay`, `dict_overlay`, `tool_versions_overlay`

The `bins_generated` profile merges `BINS` by `name` and concatenates `early`,
`generated`, and `run_all` fields across overlapping entries.

---

### `bin_composers` — [`bin_composers.py`](library/filter_plugins/bin_composers.py)

Builds action compositor bins from explicitly named bin scripts. Recognizes
`build*.sh` and `install*.sh` filenames, groups by action and scope, and emits
canonical entry-point scripts that retain the base action name.

```yaml
BINS: "{{ BINS | bin_composers }}"
# build.sh + build-kernel.sh -> build.sh with run_all: [build-kernel.sh]
# install.sh + install-user.sh -> install.sh + install-user.sh (scoped)
```

Set `compose: false` on a bin to exclude it from composition (e.g. library
scripts sourced by other scripts like `install-unit.sh`).

---

### Other filters

| Filter | File | Purpose |
|---|---|---|
| `dictify` | [`dictify.py`](library/filter_plugins/dictify.py) | Normalize mappings and list-shorthand into a mapping |
| `arrayitize` | [`arrayitize.py`](library/filter_plugins/arrayitize.py) | Place arguments into an array |
| `build_install_bins` | [`build_install_bins.py`](library/filter_plugins/build_install_bins.py) | Standard build/install bin entries for a stem name |
| `mergeKeyed` | [`mergeKeyed.py`](library/filter_plugins/mergeKeyed.py) | Compat shim over `merge_keyed` operation |
| `zim_fragment` | [`zim_fragment.py`](library/filter_plugins/zim_fragment.py) | Render zim module declarations as zmodule lines |
| `cmdline` | [`cmdline.py`](library/filter_plugins/cmdline.py) | Parse ansible-playbook command lines |
| `get` | [`get.py`](library/filter_plugins/get.py) | Safe dotted-path traversal |

## Architecture contract

See [`doc/arch.md`](doc/arch.md) for the full subsystem model, phase lifecycle,
prefix conventions, and worked examples.

See [`doc/subsys.md`](doc/subsys.md) for the subsystem contrib pattern,
`gen_*.tasks` conventions, and how to add a new subsystem.

## Task file prefixes

| Prefix | Phase | Purpose |
|---|---|---|
| `sub_*` | compile.transform | Validate input, build subsystem contracts and state |
| `gen_*` | compile.synthesis | Aggregate contribs into shared globals |
| `gen_bins` | compile.synthesis | Compose canonical build/install scripts from child actions |
| `fs_*` | fs-apply | Materialize files, links, downloads |

## Version-manager rendering

| Variable | Output | When |
|---|---|---|
| `TOOL_VERSIONS` | `.tool-versions` (asdf) | always rendered when non-empty |
| `MISE_VERSIONS` | `mise.toml` | when set; routes subsystem tool requirements into mise.toml |

When `MISE_VERSIONS` is present, no `.tool-versions` is emitted. The mise
renderer also adds an early `mise install` hook to generated `install.sh`.

## Python subsystem extensions

| Variable | Purpose |
|---|---|
| `PYTHON: true` | Activate python subsystem (uv venv, editable install) |
| `PYTHON_BUILD_COMMAND` | Replace generic `uv pip install -e .` with a custom command |
| `PYTHON_CONSOLE_SCRIPTS` | List of venv console scripts to expose as global links |

Console scripts are linked with `force: true` so they may be dangling until
`build.sh` creates the venv.

## Test suite

```sh
python tests/filter_plugins/bin_composers.test.py     #  5 tests
python tests/filter_plugins/merge_strategy.test.py     # 42 tests
python tests/filter_plugins/mergeKeyed.test.py         # 11 tests
python tests/filter_plugins/merge.test.py              # 27 tests
python tests/filter_plugins/dictify.test.py            # 10 tests
python tests/filter_plugins/zim_fragment.test.py       #  8 tests
python tests/filter_plugins/subsystem_record.test.py   # 27 tests
python tests/filter_plugins/get.test.py                #  9 tests
python tests/filter_plugins/cmdline.test.py            # 12 tests
python tests/filter_plugins/vars.test.py               #  7 tests
python tests/lookup_plugins/subsys.test.py             #  8 tests
python tests/lookup_plugins/merge_subsys.test.py       # 11 tests
```
