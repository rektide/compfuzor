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

## Typed status providers

Status declarations are grouped by their authoritative observation source.
`STATUS_PROC` is a list of typed proc-backed checks; it is intentionally broader
than one check-specific variable and narrower than a universal status schema.

```yaml
STATUS_PROC:
  - name: opencode-watchman-env
    check: mainpid-env
    unit: opencode.service
    manager: user
    expected:
      WATCHMAN_SOCK: "{{ WATCHMAN_CANONICAL_SOCKET_ABS }}"

  - name: opencode-executable
    check: exe-current
    unit: opencode.service
    manager: user
    expected: "{{ GLOBAL_BINS_DIR }}/opencode2"
```

[`sub_status_proc.tasks`](/tasks/compfuzor/sub_status_proc.tasks) validates and
normalizes the collection into one complete `SUBSYSTEM.status_proc` record.
[`gen_status_proc.tasks`](/tasks/compfuzor/gen_status_proc.tasks) merges that
provider's aggregate contribution once. Each present kind contributes one
reporter containing all matching rows:

| Check | Reporter | Check-specific contract |
|---|---|---|
| `mainpid-env` | `status-mainpid-env.sh` | `expected` is a non-empty mapping of non-sensitive string environment values. |
| `exe-current` | `status-exe-current.sh` | `expected` is an absolute executable path. |

Both checks require a concrete `.service` `unit`. `manager` is `system` or
`user`; when omitted it inherits `SYSTEMD_SCOPE` and then defaults to `system`.
Inactive units are not applicable. Query, visibility, or comparison failures
are drift.

`STATUS_PROC_BYPASS` disables all proc-backed checks. `STATUS_BYPASS` disables
the complete status domain.

The design and extension criteria are recorded in
[`draft1.gpt56s.md`](/.design/proc/draft1.gpt56s.md).

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

An authored BINS entry can tombstone a keyed subsystem contribution with
`state: absent`:

```yaml
NODEJS: true
BINS:
  - name: build-nodejs.sh
    state: absent
```

The tombstone survives the subsystem merge, is excluded before action
compositors are generated, and removes any previously rendered file. Other
contributions from the subsystem remain active. Target the contributed leaf
name (`build-nodejs.sh`), not its action compositor (`build.sh`).

To decline an entire artifact from one subsystem, set its contribution switch
`<SUBSYSTEM>_<CONTRIB>` to `false`:

```yaml
NODEJS: true
NODEJS_BINS: false
```

The Node.js subsystem remains active and still contributes `TOOL_VERSIONS`,
`ENV`, and `PKGS`; only its `BINS` payload is omitted. Use an item tombstone
instead when only selected entries should be absent. Only explicit boolean
`false` disables a contribution; undefined and other values leave it enabled.

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

1. Selects records with explicit recognized `action` metadata, otherwise scans
   filenames matching `build*.sh`, `install*.sh`, or `apply*.sh`.
2. Groups by action (`build`, `install`, or `apply`) and scope.
3. For each group, emits a compositor that retains the canonical name
   (`build.sh`, `install.sh`, `install-user.sh`).
4. The compositor's `run_all` lists child scripts to invoke after the base
   script's own content.

Explicit action metadata decouples composition from naming. For example,
`config-install.sh` declares `action: install` and joins bare `install.sh`
without a generated `install-config-*.sh` thunk. Filename discovery remains
backward compatible for existing domains.

### Phase lanes

`run_all` order follows **scheduling lanes**, not BINS arrival order. A bin
record's `phase:` field is one of `identity` / `main` / `units` / `records`
(untagged = `main`); children are stably sorted by lane, so BINS order still
decides within a lane, and a subsystem compositor lands in the earliest lane
of its leaves. Unknown phase values fail generation.

| lane | semantics | who tags it |
|---|---|---|
| `identity` | accounts/groups must exist before anything runs as/creates them | sysusers |
| `main` | default: build outputs, artifact installs, config assembly | everyone untagged |
| `units` | unit link + enable/start — needs the artifacts and identity in place | systemd |
| `records` | bookkeeping applied last (links.json records) | links |

The invariant the lanes encode: identity → artifacts → enable/start → records.
Before lanes, this ordering was accidental (BINS list order = task-file
geography), which worked only while nobody looked — units enabled before their
ExecStart binary landed crashlooped on fresh installs until Restart rescued
them. Ordering constraints live on the bin record now, not in includes order
or merge-call flags; `generatedAt: end` on systemd install bins is legacy
metadata nothing reads.

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
participates in both scoped compositors (one entry-point per scope). Explicit
scope metadata lets a neutral command such as `install-zimfw.sh` join
`install-user.sh`. Names beginning with `install-user-` or qualified as
`install-*-user.sh` also infer user scope; the old `install-*.user.sh` spelling
remains accepted for compatibility. This is how user-scope subsystems contribute
their own install step without a system-scope script that would need root.

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

The version file is a real file directly in `DIR` (no `DIR/etc` copy, no
DIR-level symlink); the only link is the repo-root one, pointing at DIR's
file, because asdf/mise resolve `getcwd()` through the physical checkout and
walk ancestors from there.

The mise renderer also contributes an `early` hook (`mise install`) to the
generated `install.sh`, so declared tools are installed before install scripts
run.

## Declared LINKS and shared link delivery

Every destination declared through `LINKS` belongs to the LINKS manager:
[`links.ts`](../files/links/links.ts) applies, reports, audits, and removes its
records from `DIR/links.json`. `compile_links` emits version 2 plans. A v2
record may declare accepted physical representations:

```yaml
- src: /deployment/etc/example.service
  dest: /etc/systemd/system/example.service
  scope: system
  policy: replace
  strategies:
    available: [link, copy]
    default: link
  compose: false
```

`strategies` and `compose` are optional v2 fields. Their absence means
`available: [link]`, `default: link`, and `compose: true`. The runtime also
accepts old version 1 manifests, but normalizes them strictly to those old
link-only/default-link/composed semantics. A v1 record that contains either v2
field is rejected with a rerender/version error rather than silently activating
mislabeled new behavior. No block or assembly representation is part of LINKS.

Zim's temporary registry manifests in `zim/install.ts` and `zim-registry.sh`
intentionally remain version 1: each declares one ordinary link and uses no v2
field. Current durable plans from `compile_links` are consistently version 2.

- `status` accepts any declared healthy representation. A healthy link uses
  the existing managed-target path contract; a healthy copy is a regular file
  whose bytes exactly match the available source. JSON rows retain `entry` and
  `target` and add the observed `representation` (`link` or `copy`). A healthy
  nondefault representation is clean, not drift. Source existence for link
  topology uses `lstat`: a dangling source symlink is still an existing link
  source, so an exact destination link is managed and a missing destination can
  be linked to it. Copy usability separately follows the source with `stat` and
  requires a regular-file referent. A copy-selected dangling or non-file source
  is `SOURCE_UNUSABLE`/`bad-source` and never falls back to link. A truly absent
  source remains `SOURCE_MISSING`/`no-source`. Foreign/dangling destination
  links, modified copies, directories, and special entries remain visible.
- `apply` with no strategy preserves any currently healthy available
  representation; a missing destination uses the record default.
  `--strategy link|copy` switches selected records explicitly and fails before
  mutation if any selected present record does not offer that strategy. The
  existing `preserve`/`fail`/`replace` policy still governs foreign regular
  files and symlinks. Directories and special entries are never replaced.
- `remove` deletes a managed link as before. It also deletes a declared copy
  only while the source is available and byte-equal; modified and
  source-unverifiable copies are preserved. Removal remains explicit—there is
  no automatic prune or reconciliation pass.
- `apply --composed` selects only records whose `compose` value is true. The
  generated `install-link-records[-user].sh` commands use this filter and do
  not forward aggregate argv into the LINKS domain. A direct `links.ts apply`
  still sees every record, while `status`, `audit`, `remove`, and direct
  `apply --id ID` always retain full declared ownership visibility.
- A scoped `install-link-records`, `install-links` compositor, and corresponding
  top-scope child are generated only when that scope has at least one composed
  record. A deployment containing only systemd `compose: false` records still
  gets `links.json`, the runtime, status, audit, and explicit remove tools, but
  no empty generic LINKS install tier. Mixed plans generate the tier only for
  scopes that participate. Previously deployed no-op scripts are not pruned
  automatically.
- Privilege routing is per system record: the default **auto** mode probes
  whether a destination is writable; `--sudo` or `COMPFUZOR_LINKS_SUDO` select
  `auto`/`always`/`never`, and sudo-mutated rows are marked. Atomic link and
  copy delivery both use this routing. User-scope records never escalate;
  explicit `always` is rejected before user mutation. `never` keeps system work
  strictly unprivileged for let-it-fail callers.

### Systemd unit publication

`install-unit.sh` applies the unit's exact `UNIT_LINK_ID` before
`daemon-reload` and enablement. Systemd unit records advertise both link and
copy, retain `policy: replace`, and set `compose: false`: activation requires
publication in the unit leaf, and the later generic records lane must neither
repeat nor undo that ordered action. Consequently
`COMPFUZOR_SYSTEMD_LINK_BYPASS`/`--skip-link` remains authoritative through a
complete install.

Runtime unit strategy precedence is:

1. explicit `--copy` or `--link`;
2. defined `SYSTEMD_INSTALL_COPY`, otherwise defined `SYSTEMD_COPY`;
3. the compiled record default.

`SYSTEMD_INSTALL_STRATEGY` configures that compiled default (`link` unless the
legacy playbook copy variables request copy). Runtime legacy values are parsed
case-insensitively: `true/yes/y/1/on` selects copy, while
`false/no/n/0/off/empty` means no override. Thus
`SYSTEMD_INSTALL_COPY=false` masks `SYSTEMD_COPY=true`, and a false value lets
LINKS preserve a healthy representation or use the compiled default when
missing; it does not force link. Invalid values fail with exit 2 before
publication. With no runtime override, the
LINKS manager intentionally receives no explicit strategy, so reinstalling
preserves either healthy representation. Explicit selection switches it. When
the manager is absent because LINKS was bypassed or the deployment predates it,
the leaf retains direct copy/link fallback and routes privileged parent
creation through its bounded `SUDO_CMD`.

User-scope units always target the user manager directory and never use sudo.
Types whose directory map is system-only (currently network and any nspawn
mapping) are rejected at compile time instead of combining an `/etc` target
with `systemctl --user`.

Sysusers records remain ordinary link-only, composed `policy: replace` records;
their installer applies the fragment before running `systemd-sysusers`.

Explicit CONFIGS consumer copy/link operations are not `LINKS` declarations:
they resolve context paths from `config.spec.json`, intentionally permit
replacing selected regular files or symlinks, and carry no ownership ledger.
They nevertheless import the same `links/delivery.ts` entry inspection and
atomic copy/link primitives used by the LINKS manager. This keeps one delivery
implementation while preserving the distinct ownership and status contracts:
LINKS representation strategy does not make systemd a CONFIG context.

## Unit aliases

A unit whose name carries the compfuzor instance suffix (`-git`, `-main`, …)
automatically gets an `[Install] Alias=` for the base name:
`apt-cacher-rs-git.service` is reachable as `apt-cacher-rs.service` once
enabled (`systemctl status apt-cacher-rs` resolves). The alias materializes
through `systemctl enable`, like every `[Install]` effect.

- `SYSTEMD_ALIAS: <name>` overrides the derived alias (type suffix appended
  when missing); `SYSTEMD_ALIAS: false` opts out — string `"false"` from
  extra-vars is honored too.
- Instanced (`@`) units never alias; `-user` separate-mode suffixes are
  stripped alongside the instance suffix.
- Explicit `SYSTEMD_INSTALLS.Alias` entries are kept and the derived alias
  appended (deduped); `Alias: false` there suppresses aliasing entirely.

Caveat: two deployments differing only by instance (a `-git` build and a
`-main` package of the same software) both derive the same base alias —
systemd resolves it to whichever enabled last. Opt one out with
`SYSTEMD_ALIAS: false`.

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
