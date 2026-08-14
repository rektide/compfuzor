# Subsystem architecture

Compfuzor models each build/runtime tool as a **subsystem**: Go, Rust, Node.js,
Bun, npm, CMake, Make, Python, kernel configuration, and others. Each subsystem
has a name, a set of environment variables that activate or bypass it, and a
`contrib` payload (`BINS`, `ENV`, `PKGS`, `ETC_FILES`, `TOOL_VERSIONS`, etc.)
that gets merged into the host config when active.

## The rule

A subsystem is **active** when:

1. Its trigger variable (`<NAME|upper>`) is truthy, AND
2. Its bypass variable (`<NAME|upper>_BYPASS`) is not truthy.

Some subsystems override `requested` with a Jinja expression (e.g. cmake checks
`CMAKE or CMAKE_ARGS or CMAKE_BUILDS`). The lookup reads `record.get("requested")`
first and falls back to checking the env var.

`valid` defaults to `true`. The state computation path is in
[`subsys.py`](../library/lookup_plugins/subsys.py#L118-L201).

## Static definitions in `vars/common.yaml`

Most subsystems are pure data under `SUBSYSTEM.<name>` in
[`vars/common.yaml`](../vars/common.yaml). No task files needed.

```yaml
SUBSYSTEM:
  go:
    contrib:
      BINS:
        - name: build.sh
          run: "{{ BINS_RUN_BYPASS is not deftruthy }}"
          basedir: repo
          generated: |
            go build -o ${GO_BIN:-$TYPE} ${GO_TARGET:-./...}
      ENV:
        GO_BIN: "{{ GO_BIN | default(omit) }}"
      TOOL_VERSIONS:
        go: true
```

The `subsys` lookup derives `requested`, `bypassed`, `valid`, `active`, and
`status` when queried.

## Reading subsystem state with `lookup('subsys')`

```yaml
# whole envelope
go_subsys: "{{ lookup('subsys', id='go') }}"

# single field
go_active: "{{ lookup('subsys', id='go', get='active', default=false) }}"

# nested field via dot path
go_bins: "{{ lookup('subsys', id='go', get='contrib.BINS', default=[]) }}"

# domain bypass (kernel children check KERNEL_BYPASS too)
modprobe_bypassed: "{{ lookup('subsys', id='kernel_modprobe', domain='kernel', get='bypassed', default=False) | bool }}"
```

## The `gen_*.tasks` pattern

Each subsystem has a `gen_*.tasks` file that merges the subsystem's `contrib`
into host globals (`BINS`, `ENV`, `PKGS`, etc.) via `merge_subsys`.

```yaml
# gen_go.tasks — the entire file
- name: "Compfuzor: synthesize go subsystem artifacts"
  set_fact:
    BINS: "{{ lookup('merge_subsys', id='go', contrib='BINS') }}"
    ENV: "{{ lookup('merge_subsys', id='go', contrib='ENV') }}"
    TOOL_VERSIONS: "{{ lookup('merge_subsys', id='go', contrib='TOOL_VERSIONS') }}"
  when: lookup('subsys', id='go', get='active', default=false) | bool
```

## BINS merge behavior

`BINS` uses the `bins_generated` merge preset from
[`cfmerge.py`](../library/filter_plugins/cfmerge.py). It merges entries by `name`
and concatenates these fields across overlapping entries:

| Concat field | Rendered by | Purpose |
|---|---|---|
| `early` | [`files/_bin`](../files/_bin) before generated content | Pre-build hooks (e.g. `mise install`) |
| `generated` | [`files/_bin`](../files/_bin) main body | The script's primary work |
| `run_all` | [`files/_bin`](../files/_bin) after generated content | Child script invocations |
| `origin_subsystems` | disarm resolver/reporting | Contributing subsystem IDs |
| `bypass_scopes` | disarm resolver/guards | Broad shell guard concerns |

Non-concat fields follow standard `merge_keyed` behavior: the incoming record
wins on key conflicts.

NVIM uses a deliberately narrower configured keyed merge: `generated`,
`origin_subsystems`, and `bypass_scopes` concatenate, while executable ordering
fields `early` and `run_all` remain later-wins.

## Automatic bin disarm

`merge_subsys` automatically annotates active incoming BINS. No routine
`bypass_scope` field is authored on subsystem records. Scope precedence is:

1. explicit `domain=` passed to `merge_subsys`;
2. `SUBSYSTEM.<id>.domain`;
3. the subsystem ID.

The resolved domain also participates in the standard subsystem active-state
calculation. Consequently `<DOMAIN>_BYPASS` suppresses an incoming
`merge_subsys` contribution as well as naming its broad rendered guard. Calls
with an explicit `active_path` retain that authored activation rule.

`origin_subsystems` always records the subsystem ID. The independent
`subsystem` BINS field still controls compositor grouping and is never used as
provenance.

[`resolve_bin_disarm`](../library/filter_plugins/bin_disarm.py) canonicalizes
the actual script basename by removing final `.sh` and an earlier dot qualifier,
replacing non-alphanumeric runs with `_`, and uppercasing. It removes tokens
already represented by the broad scope when deriving the nested action:

| Input | Scope | Action | Automatic entries |
|---|---|---|---|
| `build-go.sh` | `GO` | `BUILD` | `GO`, `GO:BUILD` |
| `install-kernel-cmdline.sh` | `KERNEL` | `INSTALL_CMDLINE` | `KERNEL`, `KERNEL:INSTALL_CMDLINE` |
| `install-rust-user.sh` | `RUST` | `INSTALL` | `RUST`, `RUST:INSTALL` |

Explicit `bypass` scalar/list entries extend automatic entries, preserving
useful global phase guards. `bypass: false` disables both automatic and explicit
outer guards. `helpers: false` remains nuclear and emits no helpers or wrapper.
For direct unannotated `.sh` records, TYPE is the fallback broad scope and raw
report label; it does not populate `origin_subsystems`. Pure generated
compositors receive no TYPE fallback. A generated canonical compositor merged
with an authored body may use that body's provenance/scope or TYPE fallback,
but its guards are body-local: a skipped body reports and continues to
`run_all`; a successful body reports completion before children run. Child
metadata is never aggregated into the parent. Sourced/library scripts must use
`bypass: false` when an outer guard's `exit 0` would be unsafe.

Normal `_bin` reporting is:

```text
+ <actual-script-name>: <derived-or-item.verb> (<origin subsystem labels>)
```

Parentheses are omitted without labels. Derived verbs are canonical action
tokens lowercased and space-separated. Init and skip reports carry the same
actual filename and labels. A direct TYPE-fallback script reports the raw TYPE
label, for example `apply-network.sh: apply network (direct-tools)`.

## Action runner: `_cf_action`

Every rendered action script (`build*.sh`, `install*.sh`, `apply*.sh`) follows
the same four-phase shape: announce, evaluate guards, run body, announce
completion. The `_cf_action` runner provides one composition point for all four,
replacing ad-hoc bypass checks and inline progress reporting.

### Shell primitives

Provided by the **`report` and `guard` helpers** (see
[`files/_helpers/`](../files/_helpers)); pulled into any bin with effective
automatic or explicit guards, or any bin that declares
`helpers: [report, guard]`. The loud/quiet gate (`_cf_loud`, from the `loud`
helper, emitted near the top of [`files/_bin`](../files/_bin)) controls all
progress output — loud unless `COMPFUZOR_QUIET` is set or `V=0`.

| Primitive | Purpose |
|---|---|
| `_cf_action_init <name> <verb> [labels]` | Print `+ name: verb (labels)` to stderr if loud |
| `_cf_action_end` | Print `complete` to stderr if loud |
| `_cf_report_skip <name> <reason> [labels]` | Print `skipped name: reason (labels)` to stderr if loud |
| `_cf_run_guard <mode> <argv...>` | Core evaluator — silent = proceed, output = skip |
| `_cf_guard_bypass <concern> [verb]` | Guard: skip if `COMPFUZOR_<CONCERN>_BYPASS` set |
| `_cf_guard_bypass_unit <concern> <unit> [verb]` | Guard: skip if `COMPFUZOR_<CONCERN>_<UNIT>_BYPASS` set |

### Guard mode bitfield

`_cf_run_guard` evaluates a command and decides pass/fail based on a mode
bitfield. Silent (no output + exit 0) = proceed. Anything else = skip, and the
first matching output becomes the skip reason.

| Bit | Signal | Reason captured |
|---|---|---|
| `0x1` | non-zero exit | `exit <N>` |
| `0x2` | non-empty stderr | stderr content |
| `0x4` | non-empty stdout | stdout content |

Priority on match: stdout (`0x4`) → stderr (`0x2`) → exit (`0x1`). The macro
default is `0x3` (exit + stderr) so bypass guards (which write reasons to
stderr) report their full message, while plain Unix commands (e.g.
`command -v gcc`) fail via exit code.

Any command can be a guard. `command -v gcc` with mode `0x1` skips when the
binary is missing. `ls /opt/populated/` with mode `0x4` skips when the directory
has contents (idempotent guard). A command that warns on stderr with mode `0x2`
is a warn-and-skip guard.

### Three entry points

| Audience | Entry point | Shape |
|---|---|---|
| Standard subsystem BINS | automatic merge metadata | Broad and nested guards derived by `files/_bin` |
| Playbook author extending policy | `bypass:` BINS field | Scalar or list; extends automatic entries |
| Subsystem author writing Jinja | `{% call cf_action(...) %}` macro | [`files/_cf_action`](../files/_cf_action) |
| Subsystem needing custom guards | macro's `guards=[...]` param | Any shell command, evaluated per mode |

### The `cf_action` macro

[`files/_cf_action`](../files/_cf_action) exports a Jinja macro for subsystem
templates:

```jinja
{% from "_cf_action" import cf_action %}
{% call cf_action(name='build-kernel', verb='rebuild kernel',
                  bypass=['KERNEL'], guards=['command -v gcc'],
                  subsystems=['kernel']) %}
make -C "${KERNEL_SRC}" modules_install
{% endcall %}
```

Renders to:

```sh
_cf_action_init "build-kernel" "rebuild kernel" "kernel"
if ! reason="$(_cf_run_guard 3 _cf_guard_bypass "KERNEL" "rebuild kernel")"; then _cf_report_skip "build-kernel" "$reason" "kernel"; _cf_action_end; exit 0; fi
if ! reason="$(_cf_run_guard 3 command -v gcc)"; then _cf_report_skip "build-kernel" "$reason" "kernel"; _cf_action_end; exit 0; fi
make -C "${KERNEL_SRC}" modules_install
_cf_action_end
```

### Bypass naming convention

Two layers, two namespaces:

| Layer | Where it gates | Namespace | Examples |
|---|---|---|---|
| Playbook (Ansible task) | `when:` clauses on tasks | bare `<C>_BYPASS` | `PKGS_BYPASS`, `MODULES_BYPASS`, `SYSTEMD_INSTALL_BYPASS` |
| Action script (rendered shell) | `_cf_guard_bypass` calls | `COMPFUZOR_<C>_BYPASS` | `COMPFUZOR_KERNEL_BYPASS`, `COMPFUZOR_ZIM_BYPASS`, `COMPFUZOR_LINK_BYPASS` |

The `COMPFUZOR_` prefix separates the shell layer from the Ansible task layer
so the two compose without collision — a playbook can set `KERNEL_BYPASS` to
skip task-level work and `COMPFUZOR_KERNEL_BYPASS` to skip the generated build
script independently.

### Hierarchical (per-unit) bypass

Some concerns have a general bypass and per-unit overrides (e.g. env). List
entries with `:` split into concern:unit:

```yaml
bypass: ['ENV', 'ENV:ZIMFW']
```

Emits `_cf_guard_bypass ENV` + `_cf_guard_bypass_unit ENV ZIMFW`. Either firing
skips the action. Policy resolves per child, so compositors invoke children
without aggregating their bypasses — `bin_composers` stays out of it.

### The `bypass:` BINS field

Scalar or list; entries extend automatic scope/action guards. The field remains
ordinary later-defined merge semantics, not a `bins_generated` concat field.
Set it to false for a sourced/library script that must not receive an outer
wrapper. Subsystems needing custom guards can still call `_cf_action` directly.

### Systemd phase controls

Systemd's internal phases remain separate from outer automatic
`SYSTEMD`/`SYSTEMD:<ACTION>` guards:

| Phase | Canonical shell variable | Temporary soak alias |
|---|---|---|
| link | `COMPFUZOR_SYSTEMD_LINK_BYPASS` | `SYSTEMD_BYPASS_LINK` |
| enable | `COMPFUZOR_SYSTEMD_ENABLE_BYPASS` | `SYSTEMD_BYPASS_ENABLE` |
| start | `COMPFUZOR_SYSTEMD_START_BYPASS` | `SYSTEMD_BYPASS_START` |

`install-dropin.sh` is intentionally nuclear (`helpers: false`), so it cannot
receive the outer helper wrapper. It enforces `COMPFUZOR_SYSTEMD_BYPASS` and
its derived nested action variable
`COMPFUZOR_SYSTEMD_INSTALL_DROPIN_BYPASS` internally before evaluating LINK or
the temporary `SYSTEMD_BYPASS_LINK` alias.

## gen_bins: action composition

[`gen_bins.tasks`](../tasks/compfuzor/gen_bins.tasks) runs after all subsystem
`gen_*.tasks` and composes canonical action entry points from child scripts.

The [`bin_composers`](../library/filter_plugins/bin_composers.py) filter:

1. Scans `BINS` for entries matching `build*.sh`, `install*.sh`, or `apply*.sh`.
2. Groups by action (`build` or `install`) and scope.
3. For each group, emits a compositor that retains the canonical name
   (`build.sh`, `install.sh`, `install-user.sh`).
4. The compositor's `run_all` lists child scripts to invoke after the base
   script's own content.

If the canonical name already has authored body fields (`early`, `generated`,
`content`, `exec`, `execs`, or `late`), the generated compositor keyed-merges
with that record. `_bin` guards those fields as one local body and always leaves
the generated `run_all` children runnable. A pure generated compositor has only
`run_all` and remains unguarded.

```yaml
# Input BINS (both tagged subsystem: kernel):
- name: build-kernel-modprobe.sh
  subsystem: kernel
- name: build-kernel-sysctl.sh
  subsystem: kernel

# After gen_bins:
- name: build-kernel.sh
  run_all: [build-kernel-modprobe.sh, build-kernel-sysctl.sh]
- name: build.sh
  run_all: [build-kernel.sh]
```

### Scope

`scope` accepts a string or list; an entry with `scope: [user, shell]`
participates in both scoped compositors (one entry-point per scope). `install-user.sh`
and any `install-user-*.sh` (e.g. `install-user-zimfw.sh`, `install-service-user.sh`)
infer the `user` scope from the filename; qualified `install-*-user.sh` names do
too. The old `install-*.user.sh` spelling remains accepted for compatibility. This is how
user-scope subsystems (zim, user systemd services) contribute their own install step
without a system-scope script that would need root.

```yaml
BINS:
  - name: install-user.sh
  - name: install-service-user.sh
    scope: [user]
    generated: systemctl --user enable ...
  - name: install-unit.sh
    compose: false    # library script, not an action
```

After gen_bins: `install-user.sh` has `run_all: [install-service-user.sh]`.
`install-unit.sh` is excluded entirely.

### Execution order

[`files/_bin`](../files/_bin) renders bin content in this order:

1. `early` (pre-build hooks)
2. `content` / `exec` / `execs`
3. `generated` (at `generatedAt` position, default end)
4. `run_all` (child invocations: `"$DIR/bin/<child>" "$@"`)
5. `late`

## Version-manager rendering

[`gen_tool_versions.tasks`](../tasks/compfuzor/gen_tool_versions.tasks) renders
tool-version artifacts. Two symmetric modes:

| Variable | Output file | Syntax |
|---|---|---|
| `TOOL_VERSIONS` | `.tool-versions` | asdf (`tool version`) |
| `MISE_VERSIONS` | `mise.toml` | TOML `[tools]` table |

Both accept mapping or list shorthand:

```yaml
MISE_VERSIONS:
  - uv              # resolves to UV_VERSION or "latest"
  - python: "3.12"  # explicit version
```

When `MISE_VERSIONS` is set, no `.tool-versions` is emitted. Subsystem tool
contributions (e.g. `python: true` from the python subsystem) are routed into
`mise.toml` automatically.

The mise renderer also contributes an `early` hook (`mise install`) to the
generated `install.sh`, so declared tools are installed before install scripts
run.

## Python subsystem extensions

### `PYTHON_BUILD_COMMAND`

Replaces the generic editable-install build body with a custom command:

```yaml
PYTHON: true
PYTHON_BUILD_COMMAND: make install
```

Without this, the python subsystem runs `uv venv` + `uv pip install -e .`.

### `PYTHON_CONSOLE_SCRIPTS`

Exposes venv console entry points as global symlinks:

```yaml
PYTHON_CONSOLE_SCRIPTS:
  - sol
  - journal
```

Each entry creates a `global: true` bin pointing at `.venv/bin/<name>`, linked
into `GLOBAL_BINS_DIR` with `force: true` (so the link may be dangling until
build creates the venv).

## Contrib artifacts and merge behavior

`merge_subsys` supports these contrib artifacts by default. The source of truth
is [`ARTIFACT_DEFAULTS`](../library/lookup_plugins/merge_subsys.py#L109-L166).

| Artifact | Kind | Default merge | Practical effect |
|----------|------|---------------|------------------|
| `BINS` | list | `bins_generated` | Merge by `name`; concatenate body fields plus disarm metadata |
| `ETC_FILES` | list | `append` | Current entries first, subsystem entries append |
| `LINKS` | list | `append` | Current entries first, subsystem entries append |
| `PKGS` | list | `append_unique` | Append and deduplicate preserving order |
| `ENV_LIST` | list | `append_unique` | Append and deduplicate preserving order |
| `ETC_DIRS` | list | `append` | Current entries first, subsystem entries append |
| `ENV` | dict | `env_overlay` (current wins) | Subsystem defaults added; playbook overrides win |
| `TOOL_VERSIONS` | dict/list | `tool_versions_overlay` (current wins) | Subsystem defaults added; user overrides win |

## Bypass variable resolution order

1. `<SUBSYSTEM_ID|upper>_BYPASS` (e.g. `RUST_BYPASS`)
2. `<DOMAIN|upper>_BYPASS` if `domain=` is set (e.g. `KERNEL_BYPASS`)
3. Extra bypass vars from `bypass=` kwarg

## Adding a new subsystem

1. Add an entry to `SUBSYSTEM` in
   [`vars/common.yaml`](../vars/common.yaml). Set `requested` only if the
   trigger logic differs from `<NAME> is truthy`.

2. Create a `gen_<name>.tasks` file — read from `lookup('subsys', id='<name>')`,
   guard with `get='active'`.

3. Add the import to
   [`tasks/compfuzor.includes`](../tasks/compfuzor.includes) with a `when:`
   guard.

4. If you need validation, add a task before generation that fails fast.

### Generated script conventions

Generated `BINS` go through [`files/_bin`](../files/_bin). That wrapper adds
the shebang, `set -euo pipefail`, env loading, default `cd`, and shell-option
restoration.

Common bin fields:

| Field | Use |
|-------|-----|
| `name` | Output filename under `BINS_DIR`. Also the merge key. |
| `replaces` | Old output filename(s) to remove before rendering this bin |
| `generated` | Shell body generated from Jinja |
| `content` | Literal shell body from a playbook |
| `run_all` | List of child bin names to invoke after this script's body |
| `early` | Shell lines rendered before generated/content body |
| `src` | Template or raw file from `files/<type>/...` |
| `basedir: repo` | Run from the checked-out repository |
| `basedir: false` | Do not emit an automatic `cd` |
| `run: true` | Run during `bins_run.tasks` |
| `global: true` | Link into `GLOBAL_BINS_DIR` |
| `force: true` | Create link even if source doesn't exist yet |
| `scope` | String or list; used by gen_bins for scoped compositors |
| `compose: false` | Exclude from gen_bins action composition |
| `origin_subsystems` | Mergeable report provenance; normally automatic |
| `bypass_scopes` | Mergeable broad guard scopes; normally automatic |
| `bypass` | Explicit guard extension; `false` disables the outer wrapper |
| `verb` | Override the report verb derived from the canonical action |
| `subsystem` | Compositor grouping only; never disarm provenance |

## File map

| File | Purpose |
|------|---------|
| [`vars/common.yaml`](../vars/common.yaml) | Static `SUBSYSTEM` defs, helper vars |
| [`library/lookup_plugins/subsys.py`](../library/lookup_plugins/subsys.py) | Lookup: resolves envelope from SUBSYSTEM + env vars |
| [`library/lookup_plugins/merge_subsys.py`](../library/lookup_plugins/merge_subsys.py) | Lookup: merges contrib artifacts into globals |
| [`library/filter_plugins/cfmerge.py`](../library/filter_plugins/cfmerge.py) | List/dict merge helpers and named presets |
| [`library/filter_plugins/bin_disarm.py`](../library/filter_plugins/bin_disarm.py) | BINS annotation, canonicalization, guard/report resolution |
| [`library/filter_plugins/bin_composers.py`](../library/filter_plugins/bin_composers.py) | Action compositor synthesis from bin filenames |
| [`library/filter_plugins/dictify.py`](../library/filter_plugins/dictify.py) | Mapping/list-shorthand normalization |
| [`library/filter_plugins/zim_fragment.py`](../library/filter_plugins/zim_fragment.py) | Zim module line rendering |
| [`tasks/compfuzor/gen_bins.tasks`](../tasks/compfuzor/gen_bins.tasks) | Bin action compositor synthesis |
| [`tasks/compfuzor/gen_tool_versions.tasks`](../tasks/compfuzor/gen_tool_versions.tasks) | `.tool-versions` and `mise.toml` rendering |
| [`tasks/compfuzor/gen_python.tasks`](../tasks/compfuzor/gen_python.tasks) | Python subsystem + console scripts |
| [`tasks/compfuzor/gen_kernel.tasks`](../tasks/compfuzor/gen_kernel.tasks) | Kernel validation and multi-child merging |
| [`files/_bin`](../files/_bin) | Bin template: resolves helpers, emits prologues/epilogues, then body |
| [`files/_helpers/`](../files/_helpers) | Per-helper bodies (`env`, `setopts`, `loud`, `report`, `guard`) |
| [`library/filter_plugins/helpers.py`](../library/filter_plugins/helpers.py) | `resolve_helpers` (three-layer merge + implications), `helper_comment` |
