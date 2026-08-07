# Compfuzor Toolkit

Compile-and-apply system for host configuration. Users declare intent in
playbooks (`.pb`); compfuzor compiles that intent into subsystem state,
synthesizes shared artifacts, then applies the result to repositories,
filesystems, services, packages, and kernel state.

## Filter plugins

The authoritative plugin catalog, signatures, undefined-value behavior, and
deprecation status live in [`library/README.md`](/library/README.md). This
section highlights the merge and bin-generation interfaces used by playbooks.

### `cfmerge`

[`cfmerge.py`](/library/filter_plugins/cfmerge.py) owns the public merge API.
Layers are variadic and `preset=` is keyword-only:

```jinja2
{{ existing | merge_list(incoming, preset='bins_generated') }}
{{ defaults | merge_dict(overrides, preset='overlay') }}
{{ records | merge_fields(profile={
  'BINS': {'preset': 'bins_generated'},
  'ENV': {'preset': 'overlay'},
}) }}
```

The filter input is the first layer and positional arguments are later layers.
Common list presets include `append`, `append_unique`, `merge_keyed`, and
`bins_generated`; common mapping presets include `overlay` and
`tool_versions_overlay`. `bins_generated` merges BINS by `name` and
concatenates `early`, `generated`, and `run_all` across collisions.

Related active filters include:

| Filter | Purpose |
|---|---|
| `normalize` | Convert one value to the registered `list`, `mapping`, `items`, or `identity` shape. |
| `combine_iff` | Overlay mappings while skipping undefined overlays and values. |
| `join2` | Normalize and join text contributions without iterating strings as characters. |

### Bin helpers and composers

[`files/_bin`](/files/_bin) selects composable `env`, `setopts`, `loud`,
`report`, and `guard` helpers. `DEFAULT_HELPERS` supplies the global baseline;
per-bin `base_helpers` and `helpers` add layers, while `helpers: false` is the
nuclear opt-out. [`resolve_helpers`](/library/filter_plugins/helpers.py)
deduplicates dependencies and emits helpers in canonical order.

[`bin_composers`](/library/filter_plugins/bin_composers.py) builds action
compositor bins from explicitly named scripts. It recognizes `build*.sh`,
`install*.sh`, and `apply*.sh`, groups by action, scope, and subsystem, and
emits canonical entry points whose `run_all` lists invoke child scripts.

```jinja2
BINS: "{{ BINS | bin_composers }}"
# build-kernel-{modprobe,sysctl}.sh -> build-kernel.sh -> build.sh
# install.sh + install-user.sh -> install.sh + install-user.sh (scoped)
```

Set `compose: false` on a bin to exclude it from composition (e.g. library
scripts sourced by other scripts like `install-unit.sh`).

### Other filters

| Filter | File | Purpose |
|---|---|---|
| `build_install_bins` | [`build_install_bins.py`](/library/filter_plugins/build_install_bins.py) | Standard build/install bin entries for a stem name |
| `zim_fragment` | [`zim_fragment.py`](/library/filter_plugins/zim_fragment.py) | Render zim module declarations as zmodule lines |
| `ansible_cmdline` | [`cmdline.py`](/library/filter_plugins/cmdline.py) | Parse ansible-playbook command lines |
| `get`, `get_path` | [`get.py`](/library/filter_plugins/get.py) | Safe dotted-path traversal |

### Deprecated soak

The retired implementations remain available for inspection but are disabled
under Ansible's `*.py` discovery: [`merge.py.deprecated`](/library/filter_plugins/merge.py.deprecated),
[`merge_strategy.py.deprecated`](/library/filter_plugins/merge_strategy.py.deprecated),
[`mergeKeyed.py.deprecated`](/library/filter_plugins/mergeKeyed.py.deprecated),
[`arrayitize.py.deprecated`](/library/filter_plugins/arrayitize.py.deprecated),
[`listify.py.deprecated`](/library/filter_plugins/listify.py.deprecated), and
[`dictify.py.deprecated`](/library/filter_plugins/dictify.py.deprecated).

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
for test in \
  tests/filter_plugins/*.test.py \
  tests/lookup_plugins/*.test.py \
  tests/integration/*.test.py
do
  python "$test" || exit 1
done
```

The integration scripts invoke real Ansible renders and syntax-check generated
bin scripts, covering helper selection and lazy same-name BINS collisions.
