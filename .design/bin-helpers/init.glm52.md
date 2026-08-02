---
type: Design
title: bin helpers — composable, opt-in template sections
description: Decompose files/_bin.header into named, independently-toggleable helpers merged across default/subsystem/author layers.
resource: /home/rektide/src/compfuzor/.design/bin-helpers/init.glm52.md
tags: [compfuzor, bins, templates]
status: draft
generated: { by: llm:glm52, at: 2026-08-02T00:00:00Z }
sources:
  - id: gen_bins-tasks
    resource: /tasks/compfuzor/gen_bins.tasks
    title: gen_bins.tasks action compositor synthesis
  - id: bin-header
    resource: /files/_bin.header
    title: current monolithic bin header
---

# bin helpers — composable, opt-in template sections

## Situation

`files/_bin` unconditionally `{% include "_bin.header" %}` for every
non-`no_header` bin ([`files/_bin:11`](/files/_bin)). That header bundles two
concerns:

1. env/setopts/DIR setup — needed by essentially every bin.
2. the `_cf_*` action-runner primitives (~50 lines, 6 functions) — needed only
   by bins that set `bypass:` or `{% call cf_action() %}`.

The result: bins like mkosi-git's `build.sh` / `image.sh` /
`run-nspawn.sh` / `vps-seed.sh` / `build-debian.sh` (which set neither) carry
~50 lines of dead function definitions. Generated compositors (`run_all`) are
the same — they use only `_cf_loud` (defined in `_bin`, not the header) for
inline `printf`, never the `_cf_action_*` functions. Only `bypass:`-set bins
and the one `cf_action` macro importer (`gen_zim.tasks`, which also sets
`bypass:`) actually call the primitives.

A secondary bug: `set -e` at [`files/_bin:2`](/files/_bin) runs *before* the
`_BIN_SETO_STATE` push at `_bin.header:12`, so the push captures an
already-`set -e`'d state and the footer restore silently re-imposes `set -e`
on a caller who had `set +e`.

A secondary complaint: `V=99` is loud because `set -x` (gated on `V>2`) is
bundled with the setopts machinery; a bin can't opt out of xtrace without
opting out of everything.

## Direction (locked)

Decompose the header into **named helpers**, each independently toggleable,
merged across three layers (default / subsystem / author). Template-time
conditional inclusion — no runtime sourcing, no shared lib file.

### The five helpers

| helper | description (comment emitted before inclusion) | prologue | epilogue |
|---|---|---|---|
| `env` | default $DIR and source env.export | DIR default + `env.export` source | — |
| `setopts` | strict shell (errexit/nounset/pipefail) + nullglob, save/restore | push `_BIN_SETO_STATE` + `set -euo pipefail` + `shopt -s nullglob` | pop + `eval "$__saved"` (current `_bin.footer`) |
| `loud` | progress gate + xtrace at V>2 | `_cf_loud` gate + `(( ${V:-0} > 2 )) && set -x` | — |
| `report` | action progress + skip messaging | `_cf_action_init` / `_cf_action_end` / `_cf_report_skip` | — |
| `guard` | guard evaluator + COMPFUZOR_*_BYPASS predicates | `_cf_run_guard` / `_cf_guard_bypass` / `_cf_guard_bypass_unit` | — |

`set -e` is folded **into** `setopts` (after the push) so the push captures the
caller's true original state and the restore is correct. The always-on floor
becomes literally just the shebang — everything else is a helper.

### Canonical emission order

Fixed by the registry, independent of the order helpers were requested:
**env → setopts → loud → report → guard**. This preserves the current physical
ordering and guarantees the setopts push precedes loud's `set -x` (so the push
captures pre-xtrace state). Epilogues emit in reverse order (LIFO) so setopts
restores correctly.

### Three-layer merge

| layer | field | scope | semantics |
|---|---|---|---|
| **global default** | `DEFAULT_HELPERS` (var) | all bins | baseline floor; overridable by setting the var at playbook scope |
| **subsystem base** | `base_helpers` (per-bin) | this bin type | list = merge on top of default; `False` = suppress this layer; absent = nothing |
| **author add-on** | `helpers` (per-bin) | this bin | list = merge; `False` = **nuclear opt-out** (no helpers at all); absent = nothing |

**Resolved = `DEFAULT_HELPERS ∪ item.base_helpers ∪ item.helpers`**, then
implications, then reordered to canonical. `base_helpers: False` drops only the
subsystem layer; `helpers: False` zeroes everything (= legacy `no_header`).

### Implications

- `item.bypass` set (and not False) → add `report` + `guard`.
- `report` in resolved set → add `loud` (report funcs read `_cf_loud`).

These run after the union, so `bypass:` continues to work exactly as today
without the author knowing about `helpers`.

### `no_header` legacy alias

`no_header: true` (used by `install-dropin.sh`, `surround-51-activate`,
`surround-51-wire` — none of which use any `_cf_*`) becomes an alias for
`helpers: False` (nuclear opt-out). Shebang stays as the floor.

### Comment format

Before each inclusion the template emits: `# <name> helper: <description>`,
with descriptions hardcoded in the registry.

## What changes

- **new** [`library/filter_plugins/helpers.py`](/library/filter_plugins/helpers.py)
  — `resolve_helpers(item, default_helpers)` filter: the 3-layer merge,
  implications, canonical-order dedupe. Also exports `HELPERS_DESCRIPTIONS`.
- **new** [`files/_helpers`](/files/_helpers) — `helper_prologue(name)` /
  `helper_epilogue(name)` macros holding each helper's body.
- **rewrite** [`files/_bin`](/files/_bin) — resolve via the filter, emit
  comment + prologue per helper (canonical order), existing body, epilogue per
  helper (reverse order).
- **remove** [`files/_bin.header`](/files/_bin.header) and
  [`files/_bin.footer`](/files/_bin.footer) (absorbed into `_helpers`).
- **update** [`library/filter_plugins/bin_composers.py`](/library/filter_plugins/bin_composers.py)
  — tag generated compositors with `base_helpers: ['env', 'setopts', 'loud']`
  (compositors use `_cf_loud` for inline `printf`, not report/guard).
- **update** [`vars/common.yaml`](/vars/common.yaml) — add
  `DEFAULT_HELPERS: [env, setopts, loud]`; drop the now-unused
  `FILES_BIN_HEADER` / `FILES_BIN_FOOTER` lookups.
- **tests** — `tests/filter_plugins/helpers.test.py` for `resolve_helpers`;
  extend `bin_composers.test.py` for the compositor `base_helpers` tag.
- **docs** — `doc/bins.md`, `doc/subsys.md`.

## Defaults

`DEFAULT_HELPERS = [env, setopts, loud]` — the current de-facto floor minus the
dead report/guard. Net impact:

- `bypass:` bins today: default + implication(report,guard) = all five,
  byte-equivalent rendering.
- mkosi-git-style plain bins: default only = shed ~50 lines, no author action.
- compositors: tagged `base_helpers: [env, setopts, loud]` = shed report/guard.
- subsystem bins: default ∪ subsystem base ∪ implications.

## Decisions deferred

- Splitting a `trace` helper out of `loud` (to control xtrace independently of
  the progress gate): not now; `loud` owns both. Revisit if a real consumer
  wants the split.
- `no_helpers`-style per-helper exclusion: not needed — `base_helpers: False`
  (layer suppress) and `helpers: False` (nuclear) cover the cases that came up.
