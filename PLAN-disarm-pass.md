# Disarm Pass — per-concern `_BYPASS` across all action scripts

Epic: [`compfuzor-disarm-pass`](.beads/issues.jsonl) (`.beads/issues.jsonl`).
Convention home: [`doc/subsys.md`](doc/subsys.md) § Action runner.

## Goal

Every generated action script (`build*.sh` / `install*.sh` / `apply*.sh`) honors
a named `<CONCERN>_BYPASS` so an operator can skip one deploy concern (kernel
rebuild, systemd enable, zim fragment promotion, a language build/install, …) in
isolation — without editing the playbook or nulling ENV vars.

Two layers, two namespaces (already documented in
[`doc/subsys.md`](doc/subsys.md) § Bypass naming convention):

| Layer | Where it gates | Namespace | Examples |
|---|---|---|---|
| Playbook (Ansible task) | `when:` clauses | bare `<C>_BYPASS` | `PKGS_BYPASS`, `MODULES_BYPASS` |
| Action script (rendered shell) | `_cf_guard_bypass` calls | `COMPFUZOR_<C>_BYPASS` | `COMPFUZOR_KERNEL_BYPASS`, `COMPFUZOR_ZIM_BYPASS` |

## Current state — what exists, what's missing

### DONE (the foundation is in place)

- **Shell primitives** in [`files/_bin.header`](files/_bin.header): `_cf_action_init`,
  `_cf_action_end`, `_cf_report_skip`, `_cf_run_guard` (mode bitfield), and the
  two bypass guards `_cf_guard_bypass <concern>` / `_cf_guard_bypass_unit`.
- **Loud/quiet gate** at the top of [`files/_bin`](files/_bin): `_cf_loud`, off
  when `COMPFUZOR_QUIET` set or `V=0`. All primitives respect it.
- **`cf_action` Jinja macro** in [`files/_cf_action`](files/_cf_action): wraps a
  `{% call %}` body with announce → guards → body → announce.
- **`doc/subsys.md` § Action runner** is comprehensive (primitives, guard modes,
  three entry points, naming, hierarchical per-unit bypass).
- **Two reference scripts** follow the convention (by intent):
  [`files/install-zim.sh`](files/install-zim.sh)-adjacent `install-user-zimfw.sh`
  (`ZIM_BYPASS`, hand-rolled inline) and `gdm-no-suspend.etc.pb`'s
  `build-link.sh`/`install-link.sh` (`COMPFUZOR_LINK_BYPASS`, hand-rolled inline).

### THE GAP — `bypass:` BINS field is documented but NOT implemented

[`doc/subsys.md`](doc/subsys.md) § "The `bypass:` BINS field" says:

> Scalar or list; when set, `files/_bin` wraps the rendered body in a `cf_action`
> call. This is the declarative shorthand for the 80% case.

**[`files/_bin`](files/_bin) never reads `item.bypass`.** Confirmed by reading
the template. This is the linchpin: until `_bin` consumes `bypass:`, every
subsystem must hand-roll the guard (or use the macro inline), which is why the
vast majority of action scripts have no guard at all.

### Consequence — most action scripts are unguarded

Survey of contributors (from [`doc/subsys.md`](doc/subsys.md) file map + grep):

| Contributor | Scripts | Guarded? |
|---|---|---|
| `gen_zim` | `install-user-zimfw.sh` | yes (inline) |
| `gen_link` prototype (gdm-no-suspend) | `build-link.sh`, `install-link.sh` | yes (inline) |
| `gen_go` / `gen_nodejs` / `gen_bun` / `gen_rust` / `gen_python` / `gen_npm` / `gen_bazel` / `gen_cmake` / `gen_make` | `build-<lang>.sh`, `install-<lang>.sh` | **no** |
| `gen_kernel` (modprobe/sysctl/sysfs/params/bls) | `build-kernel-modprobe.sh`, `install-kernel-sysctl.sh`, `apply-kernel-sysfs.sh`, … | **partially migrated; inventory pending** |
| `vars_systemd_unit` | `install-service*.sh`, `install-socket*.sh`, `install-unit.sh`, `install-dropin.sh` | **divergent vocab** (see below) |
| playbook-authored `content:` BINS | across the tree | **mostly no** |

### Divergent vocabulary — systemd phase flags

[`files/systemd/install-unit.sh`](files/systemd/install-unit.sh) and
[`files/systemd/install-dropin.sh`](files/systemd/install-dropin.sh) implement
their **own** fine-grained scheme: `SYSTEMD_BYPASS_LINK` / `SYSTEMD_BYPASS_ENABLE`
/ `SYSTEMD_BYPASS_START` env vars plus `--bypass-link` / `--bypass-enable` /
`--bypass-start` CLI flags. This is richer than `_cf_guard_bypass` (per-**phase**,
not just per-concern) and should be **preserved**, but reconciled with the
`COMPFUZOR_*` namespace so the two compose.

## Design

### Key fact: all non-`raw` action scripts flow through `files/_bin`

Per [`tasks/compfuzor/bins.tasks`](tasks/compfuzor/bins.tasks), a BINS entry is
rendered through [`files/_bin`](files/_bin) (and thus gets `_bin.header`
primitives) whenever it has **any** of `content` / `generated` / `exec` /
`run_all` / `early` / `late`, **or** is a non-raw `src:`/template script (the src
is loaded via `lookup('template', …)` and injected as `content`). Only
`raw: True` entries are `copy`-ed verbatim — and those are status reporters
(`status-*.ts`), not action scripts.

**Implication**: wiring `item.bypass` into `_bin` covers **every** action script
that matters — generated language scripts, `src:` kernel/systemd scripts, and
playbook `content:` scripts — with a single template change. No per-script
plumbing required for the common case.

### Step 1 (linchpin): `_bin` consumes `item.bypass`

In [`files/_bin`](files/_bin), when `item.bypass` is set, wrap the
content/generated/run_all body region in a `cf_action` call. Concretely, between
the header include and the body, emit the macro invocation:

```jinja
{% if item.bypass is defined and item.bypass %}
{% from "_cf_action" import cf_action %}
{% set _b = item.bypass if item.bypass is iterable and item.bypass is not string else [item.bypass] %}
{% call cf_action(name=item.name|basename, verb=item.verb|default('running'), bypass=_b, guards=item.guards|default([])) %}
{% endif %}
   …existing early/content/generated/run_all/late rendering…
{% if item.bypass is defined and item.bypass %}
{% endcall %}
{% endif %}
```

A new optional `verb:` BINS field feeds the announce line
(`build-kernel: rebuild kernel`); defaults to `running`.

Note the `run_all` child-invocation block already lives inside the wrapped
region, so a compositor entry-point (`build.sh`/`install.sh`) whose children
carry their own `bypass:` will short-circuit per-child (each child is a separate
process via `"$DIR/bin/<child>" "$@"`). The compositor itself need not aggregate
child bypasses — **per-child guards** is the composition model, matching what
[`doc/subsys.md`](doc/subsys.md) § Hierarchical bypass already states.

### Step 2: convert subsystem contribs (the 80% — one line each)

Each `gen_*` subsystem's contrib `BINS` in [`vars/common.yaml`](vars/common.yaml)
gains a `bypass:` field. The concern name is the subsystem id (upper-cased),
matching the playbook-layer `<NAME>_BYPASS` so the two layers read as one
concept to the operator:

| Subsystem | Script(s) | `bypass:` |
|---|---|---|
| `go` | `build-go.sh`, `install-go.sh` | `GO` |
| `nodejs` | `build-nodejs.sh`, `install-nodejs.sh` | `NODEJS` |
| `bun` | `build-bun.sh`, `install-bun.sh` | `BUN` |
| `rust` | `build-rust.sh`, `install-rust.sh`, `install-rust.user.sh` | `RUST` |
| `python` | `build-python.sh`, `install-*.sh` (console scripts) | `PYTHON` |
| `npm` | `build-npm.sh`, `install-npm.sh` | `NPM` |
| `bazel` | `build-bazel.sh`, `install-bazel.sh` | `BAZEL` |
| `cmake` | `build-cmake.sh`, `install-cmake.sh` | `CMAKE` |
| `make` | `build-make.sh` | `MAKE` |

Because `_bin` now honors `bypass:`, this is the entire change — no inline shell.

### Step 3: convert kernel leaves

The `_kernel_*_bins` lists in [`vars/common.yaml`](vars/common.yaml) reference
`src:` scripts (rendered through `_bin`, so they get primitives). Add `bypass:`
per leaf, using the **domain** `KERNEL` so one `COMPFUZOR_KERNEL_BYPASS` disarms
all kernel action scripts, plus the leaf concern for granularity:

| Leaf | Scripts | `bypass:` |
|---|---|---|
| `_kernel_modprobe_bins` | `build-kernel-modprobe.sh`, `install-kernel-modprobe.sh`, `apply-kernel-modprobe.sh`, `install-kernel-cmdline.sh` | `['KERNEL', 'KERNEL_MODPROBE']` |
| `_kernel_sysctl_bins` | `build-kernel-sysctl.sh`, `install-kernel-sysctl.sh`, `apply-kernel-sysctl.sh` | `['KERNEL', 'KERNEL_SYSCTL']` |
| `_kernel_sysfs_bins` | `build-kernel-sysfs.sh`, `install-kernel-sysfs.sh`, `apply-kernel-sysfs.sh` | `['KERNEL', 'KERNEL_SYSFS']` |
| `_kernel_params_bins` | `install-kernel-params.sh` | `['KERNEL', 'KERNEL_PARAMS']` |
| `_kernel_bls_bins` | `install-kernel-bls.sh` | `['KERNEL', 'KERNEL_BLS']` |

Domain-level `KERNEL` mirrors the `domain='kernel'` already used by the
[`subsys`](library/lookup_plugins/subsys.py) lookup for the playbook layer
(see Bypass variable resolution order in
[`doc/subsys.md`](doc/subsys.md)). The hierarchical `cf_action` rendering (one
guard per list entry) means either `COMPFUZOR_KERNEL_BYPASS` **or**
`COMPFUZOR_KERNEL_SYSCTL_BYPASS` skips the sysctl scripts.

### Step 4: reconcile systemd phase flags

[`files/systemd/install-unit.sh`](files/systemd/install-unit.sh) /
[`files/systemd/install-dropin.sh`](files/systemd/install-dropin.sh) keep their
fine-grained link/enable/start phases — that granularity is valuable and has no
equivalent in `_cf_guard_bypass`. Two changes only:

1. **Namespace under `COMPFUZOR_`**: rename `SYSTEMD_BYPASS_LINK` →
   `COMPFUZOR_SYSTEMD_LINK_BYPASS`, etc. (back-compat alias: accept old name with
   a deprecation stderr line for one cycle). This keeps the shell and Ansible
   namespaces disjoint per the convention table.
2. **Add an umbrella guard at the top** of each systemd script via the now-wired
   `bypass:` field on its BINS entry (`bypass: SYSTEMD`), so
   `COMPFUZOR_SYSTEMD_BYPASS` disarms the whole concern while the phase flags
   still allow surgical skip of link/enable/start within a real run.

The systemd install scripts (`install-service.sh`, `install-socket.sh`, …)
generated by [`tasks/compfuzor/vars_systemd_unit.tasks`](tasks/compfuzor/vars_systemd_unit.tasks)
gain `bypass: SYSTEMD` on their BINS entries; they invoke `install-unit.sh`
internally, which retains its phase flags.

### Step 5: migrate the two DONE references to the helper

- `install-user-zimfw.sh` in [`gen_zim.tasks`](tasks/compfuzor/gen_zim.tasks):
  replace the hand-rolled `if [ -n "${ZIM_BYPASS:-}" ]…` block with
  `bypass: ZIM` on the BINS entry (delete the inline gate; keep the host-not-found
  fallback as a plain body since that's logic, not a bypass).
- `gdm-no-suspend.etc.pb` `build-link.sh` / `install-link.sh`: replace inline
  gates with `bypass: LINK` on each BINS entry. (This also retires the
  hand-rolled loud/quiet check — `_cf_loud` handles it.)

After this, **no action script should contain a hand-rolled bypass check**;
`grep -rn 'COMPFUZOR_.*_BYPASS' files/` should only hit `_bin.header` (the
helper) and `_cf_action` (the macro).

### Step 6: playbook-authored `content:` BINS

These are long-tail. The path is identical (add `bypass: <CONCERN>`), but the
concern name is playbook-specific. Approach:

- Convert as playbooks are touched (opportunistic), **plus** a focused sweep of
  the highest-impact playbooks (anything with `install-*.sh` that writes into
  `/etc`, links into `/usr/local/bin`, or enables systemd units).
- Document the `bypass:` field in the "Generated script conventions" table in
  [`doc/subsys.md`](doc/subsys.md) (it's in the § "The `bypass:` BINS field"
  prose but missing from the common-bin-fields table).

### Step 7: inventory / drift check

Acceptance criterion #4 from the epic. Add a test under [`tests/`](tests/) that:

1. Greps `vars/common.yaml` `SUBSYSTEM` + `_kernel_*_bins` for action-script BINS
   entries (`build*.sh`/`install*.sh`/`apply*.sh`) and asserts each has a
   `bypass:` field.
2. Greps `files/` for action scripts and asserts none contain a hand-rolled
   `COMPFUZOR_…_BYPASS` / `*_BYPASS` inline check (only `_bin.header` +
   `_cf_action` may reference the primitive names).
3. Greps playbooks (`.pb`) for `content:` action scripts and reports (warn, not
   fail) those missing `bypass:` — the long-tail tracker.

This makes drift visible when a new subsystem or playbook lands without a guard.

## Phasing

Each phase is independently shippable. No time estimates (per project policy).

1. **Foundation** — Step 1 (`_bin` consumes `bypass:`) + extend the
   common-bin-fields doc table. Unblocks everything else. Verify by rendering one
   playbook (`gdm-no-suspend.etc.pb`) and confirming the wrapped output.
2. **Language subsystems** — Step 2 (the 9 `gen_*` contribs). Mechanical,
   one-line-per-script.
3. **Kernel leaves** — Step 3 (5 leaves). Verify the domain `KERNEL` umbrella
   fires across all leaves.
4. **Systemd reconciliation** — Step 4 (namespace + umbrella). Back-compat alias
   for the old `SYSTEMD_BYPASS_*` names.
5. **Reference migration** — Step 5 (zim + gdm-no-suspend). Retires the last
   hand-rolled gates.
6. **Playbook sweep + drift test** — Step 6 (high-impact playbooks) + Step 7
   (the inventory test, so future drift is caught).

## Acceptance (from the epic)

- [ ] Every generated action script honors a named `<CONCERN>_BYPASS`.
- [ ] The skip message respects `COMPFUZOR_QUIET` / `V=0` (loud otherwise) —
      satisfied by routing through `_cf_report_skip` / `_cf_loud`, not hand-rolled.
- [ ] The convention is documented once (`doc/subsys.md`); subsystems reference
      it via a `bypass:` field rather than copying shell.
- [ ] An inventory test exists so drift is visible (Step 7).

## Files touched

| File | Change |
|---|---|
| [`files/_bin`](files/_bin) | Consume `item.bypass` → wrap body in `cf_action` (Step 1) |
| [`vars/common.yaml`](vars/common.yaml) | `bypass:` on every `SUBSYSTEM` + `_kernel_*_bins` action BINS (Steps 2–3) |
| [`tasks/compfuzor/vars_systemd_unit.tasks`](tasks/compfuzor/vars_systemd_unit.tasks) | `bypass: SYSTEMD` on install-script BINS entries (Step 4) |
| [`files/systemd/install-unit.sh`](files/systemd/install-unit.sh), [`files/systemd/install-dropin.sh`](files/systemd/install-dropin.sh) | Namespace phase flags under `COMPFUZOR_SYSTEMD_*` + back-compat alias (Step 4) |
| [`tasks/compfuzor/gen_zim.tasks`](tasks/compfuzor/gen_zim.tasks) | Replace inline gate with `bypass: ZIM` (Step 5) |
| [`gdm-no-suspend.etc.pb`](gdm-no-suspend.etc.pb) | Replace inline gates with `bypass: LINK` (Step 5) |
| [`doc/subsys.md`](doc/subsys.md) | Add `bypass:` / `verb:` to common-bin-fields table (Step 1) |
| [`tests/`](tests/) | New drift-check test (Step 7) |
