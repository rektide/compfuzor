---
type: Review
title: "merge-star draft0 — reviewer pass (ds4f)"
description: Independent review of draft0's fixed-step pluggable merge pipeline, grounded against merge.py, merge_strategy.py, helpers.py, arrayitize.py, and the live consumer surface (merge_subsys lookup).
resource: /home/rektide/src/compfuzor/.design/merge-star/review0.ds4f.md
tags: [compfuzor, merge, pipeline, review]
status: draft
generated: { by: llm:ds4f, at: 2026-08-02T00:00:00Z }
sources:
  - id: draft0
    resource: /.design/merge-star/draft0.md
    title: merge-star draft0 — fixed-step, pluggable merge pipeline
  - id: merge-py
    resource: /library/filter_plugins/merge.py
    title: merge.py (743 lines) — merge_list/merge_dict/merge_*_subsys/subsys_publish
  - id: merge-strategy-py
    resource: /library/filter_plugins/merge_strategy.py
    title: merge_strategy.py (327 lines) — merge_with_strategy + STRATEGY_PROFILES
  - id: helpers-py
    resource: /library/filter_plugins/helpers.py
    title: helpers.py — resolve_helpers
  - id: arrayitize-py
    resource: /library/filter_plugins/arrayitize.py
    title: arrayitize.py — 88 single-pipe call sites, 0 variadic
  - id: mergeKeyed-py
    resource: /library/filter_plugins/mergeKeyed.py
    title: mergeKeyed.py — compat shim over merge_with_strategy
  - id: listify-py
    resource: /library/filter_plugins/listify.py
    title: listify.py — 4th list normalizer + a `concat` filter
  - id: merge-subsys-lookup
    resource: /library/lookup_plugins/merge_subsys.py
    title: merge_subsys.py — the primary consumer; ARTIFACT_DEFAULTS registry
---

# Review of merge-star `draft0`

## What's up

`draft0` proposes collapsing the merge family (`merge.py` + `merge_strategy.py`
+ helpers + arrayitize) onto **one fixed-shape pipeline** —
`collect → combine → refine → extract` — with a bounded, registered vocabulary
at each pluggable stage, so that strategies become *presets* (`combine` +
`refine[]` tuples) and `resolve_helpers` stops being special. It grows out of the
bin-helpers decomposition (helpers resolver delegation to `merge_list`), and the
doc's stated purpose is a critique-seeking draft: the maps in §3–§5 are
explicitly up for pushback.

This review is grounded in the actual code, not just the draft's self-report. I
read `merge.py`, `merge_strategy.py`, `helpers.py`, `arrayitize.py`, the
`merge_subsys` lookup plugin, `mergeKeyed.py`, `listify.py`, and grep'd the
consumer surface (`.tasks`, `.pb`, `vars/`, `files/`).

## Verdict up front

**The thesis is right and the draft is mostly accurate.** A fixed pipeline shape
with closed vocabularies is the correct architecture for this codebase: it
replaces three string-switches with a lookup table, makes `resolve_helpers` an
ordinary preset invocation, and kills real duplication. The staging (§7) is
sensible and the "explicitly open" honesty is a strength, not weakness.

**But the draft's duplication map is built from the wrong evidence.** It reads
the *implementation* files but not the *consumer*. The live consumer of the
merge family is the `merge_subsys` lookup plugin
([`merge_subsys.py`](/library/lookup_plugins/merge_subsys.py)), whose
`ARTIFACT_DEFAULTS` table is a **third strategy registry** — and it's the one
actually exercised by playbooks. Two profiles the draft treats as first-class
(`subsystem_contrib`, `subsystem_artifacts`) appear to have **zero live
callers**. That reshapes stage G materially. Details below.

## Claims verified against the code

| draft claim | verdict |
|---|---|
| `_merge_keyed` defined twice | ✅ true (`merge.py:259`, `merge_strategy.py:16`) — **but not behaviorally identical**, see below |
| `bins_generated` disagrees (`[early,generated,run_all]` vs `[generated]`) | ✅ true (`merge.py:53` vs `merge_strategy.py:86`) |
| `_append_unique_by` implemented twice | ✅ true (`merge.py:313` + inline at `merge_strategy.py:161`) |
| `_as_list` / `_dedupe_preserve` imported, not duplicated | ✅ true |
| two profile registries, overlapping names | ✅ **understated** — there are **three** (see below) |
| `resolve_helpers` hardcodes `bypass→[report,guard]`, `report→loud`, canonical order | ✅ true (`helpers.py:78-89`) |
| `collect` stage "done" (`_collect_payloads`) | ✅ true (`merge.py:425`) |
| `extract` stage "done" (`get_path`) | ✅ true |
| `arrayitize` ~50 single-pipe sites, 0 variadic | ✅ true — I count 88 `\| arrayitize` tokens, and the variadic/multi-arg form has no live callers |
| `_arrayitize` copy in `bin_composers.py` | ✅ true (`bin_composers.py:23`) |

### Correction 1 — the two `_merge_keyed` are NOT "byte-near-identical" in behavior

On string-concat of `concat_fields`, `merge.py` uses
`_concat_strings_preserving_tags` (tag-aware, `merge.py:296`), while
`merge_strategy.py` uses plain `existing + "\n" + value`
(`merge_strategy.py:46`). **The merge_strategy copy silently drops Ansible
datatag preservation.** That is a latent bug, not a trivial dedup. When stage D
deletes the duplicate, it must unify *onto the tag-preserving version* and treat
any divergence as a fix, not a no-op merge. Worth calling out in the exit
criteria so it isn't lost in a mechanical dedupe.

### Correction 2 — the duplication map is missing the third registry and the shims

The draft scopes the problem as "two modules, partly overlapping." There are
more seams the consolidation must account for:

- **`ARTIFACT_DEFAULTS` in `merge_subsys.py`** (`merge_subsys.py:111-166`) — a
  per-artifact strategy table: `BINS→bins_generated`, `ETC_FILES→append`,
  `LINKS→append`, `PKGS→append_unique`, `ENV_LIST→append_unique`,
  `ETC_DIRS→append`, `ENV→env_overlay`, `ENV_PRIO→env_overlay`,
  `TOOL_VERSIONS→tool_versions_overlay`. This is the registry the `.tasks`
  files actually hit (`gen_rust`, `gen_python`, `gen_go`, `gen_npm`, `gen_make`,
  `gen_desktop`, …). Stage G's "one profile registry" list omits it.
- **`mergeKeyed.py`** — a compat shim (`mergeKeyed.py:11`) implemented *through*
  `merge_with_strategy`. It's a caller of the thing stage E reimplements; it
  must be in the migration list, and its `{items: {op:…}}` record shape shows
  exactly what per-field preset dispatch needs to keep working.
- **`listify.py`** — a *fourth* list normalizer, plus a `concat` filter
  (`listify.py:17`) that is literally the pipeline's `concat` combine wearing a
  filter costume. Near-dead (2 + 1 usages in vars), but stage F's "one
  list-normalizer" exit criterion is not met if `listify` survives.

## The big finding: the consumer surface changes stage G

The draft's §5 profile table and stage G treat `subsystem_contrib` and
`subsystem_artifacts` (merge_strategy's `STRATEGY_PROFILES`) as live. They are
**dead in playbook terms**: nothing outside `merge_strategy.py` references them
(only `merge_with_strategy` *tests* do). The live per-field/per-artifact map is
`ARTIFACT_DEFAULTS`. Consequences:

1. Stage G's "one registry" must be scoped to **what's actually used**:
   `ARTIFACT_DEFAULTS` (live), the `merge.py` list/dict profiles (live via the
   lookup), and `bins_generated` (live, but disagreeing). `subsystem_contrib` /
   `subsystem_artifacts` should be either deleted or re-derived from
   `ARTIFACT_DEFAULTS`, not consolidated as equal citizens.
2. There's a **third `bins_generated`-adjacent disagreement the draft doesn't
   see**: `ARTIFACT_DEFAULTS` says `BINS → bins_generated` (merge_keyed), while
   `STRATEGY_PROFILES.subsystem_contrib` says `BINS → append`. Two per-field
   maps, different BINS strategies. Whoever "wins" affects how many distinct
   `[early, generated, run_all]` concat fields actually reach playbooks.

So the consolidation target isn't "merge.py ∪ merge_strategy.py" — it's "the
merge family **including the lookup plugin**," and the exit criterion "single
source of truth for every named strategy/profile" needs `ARTIFACT_DEFAULTS`
folded in.

## Weighing in on the draft's explicit open critiques

The draft asked for pushback on specific questions. My leans:

- **`skip` its own stage?** Keep folded into `collect`, as the draft leans.
  Skip filters *during* gather (source + element level, `merge.py:425`); a
  separate `filter` stage adds a slot you can't compose anything into. It's a
  `collect` argument, not a stage.
- **`dedupe_by` refine vs combine?** Refine. `append_unique_by` is genuinely
  `concat + last-per-key-wins dedupe`; the code mis-files it as a combine-op and
  the draft's move is correct. **But** pin the semantics: `dedupe` is
  first-seen-wins, `dedupe_by` is last-seen-per-key-at-first-position-wins.
  That asymmetry is real (see `merge.py:328-345`) and will trip users if
  undocumented.
- **`keyed_fold` combine vs concat+refine?** Combine. Merging overlapping
  records field-by-field with `concat_fields` is inherently pairwise-ordered;
  a refine (whole-value transform) can't reproduce it on a concatenated list.
  Keep as combine.
- **One entry point vs two?** Two (`merge_list`/`merge_dict`), as the draft
  defaults. The combine vocabulary splits by type anyway, and `merge_with_strategy`
  is the *type resolution* — its per-field dispatch picks the list or dict
  preset. A polymorphic `merge` would just reintroduce the type switch.
- **Where does `dictify` live?** Not in `collect` — a collect-level map would
  run `dictify` on payloads destined for non-union combines. Register it as its
  own combine (`dictify_union`) so the preset is honest:
  `tool_versions_overlay = (dictify_union, [])`. Closed vocabulary, no new slot.
- **Slot names?** `collect/combine/refine/extract` is fine; the draft's
  `gather → fold → shape → pick` alternative is worse (shapes *is* the refine).
  Keep. Minor gripe: the mermaid diagram renders one `combine` box containing
  `union | replace` (dict-only) alongside `concat | keyed_fold` (list-only),
  which visually implies a single vocabulary. Add the type-split to the diagram.

## New issues the draft doesn't raise

1. **`helpers: False` nuclear opt-out is dropped by the §6 preset.** Layer-skip
   (`skip = "false,none,undefined"`) means *that layer* contributes nothing.
   But `helpers.py:68` — `helpers: False` (or legacy `no_header`) empties the
   **whole result**, not just the author layer. The §6 preset, as sketched,
   would turn `helpers: False` into "skip the author layer" → result =
   `defaults + base_helpers`, NOT `[]`. Preserving the opt-out needs a distinct
   policy the sketch doesn't have (a "poison layer" / whole-output-empty
   condition). Either stage D must model it, or the draft must explicitly decide
   to change that behavior. Currently it silently drops a behavior.
2. **`replace` has no type-agnostic home.** `merge_with_strategy`'s `replace`
   applies to *any* field — scalar, list, dict (`merge_strategy.py:301`). The
   draft files it under **dict combines only**. If stage E makes
   `merge_with_strategy` = per-field preset dispatch, `replace` must be a valid
   preset for a scalar or list field too. The combine vocabulary's type-split
   needs a third bucket (or "any-type" combines) or per-field dispatch breaks.
3. **`merge_with_strategy`'s record-level kwargs are a second collect.** The
   draft says stage E "composes on top of the pipeline," but `into`, `single`,
   `aggregate`, `include_aggregate`, `payload_path` are *record-gathering*
   concerns — a collect analog at a different granularity than `_collect_payloads`
   (which gathers *payloads*, not *records*). Stage E should enumerate these and
   show how they map, or the "composes on top" claim is under-specified.
4. **`_dedupe_preserve` keys on `str(value)`** (`merge.py:41`). Promoting `dedupe`
   to a first-class refine makes this wart load-bearing: `[1, "1"]` dedupes to
   `[1]`, and two equal-content-differently-ordered dicts don't dedupe. Pre-existing,
   but decide (fix vs document) before it's "the" dedupe refine.
5. **Stage H may be dead-code work, not alignment.** `subsys_publish`,
   `merge_list_subsys`, `merge_dict_subsys` have **no live callers** in tasks,
   templates, or files. Re-frame stage H: first delete-or-confirm, then align.
6. **`mergeKeyed` must be in the migration surface** (it's the one thing that
   keeps `merge_with_strategy` reachable from real playbooks via
   `vars_nvim.tasks` / `vars_mcp.tasks`). It's absent from the draft's reference
   list.

## What the draft gets right

- **Bounded design space is the correct discipline.** "Two closed-vocabulary
  questions, not invent a pass-chain" is the exact argument that justifies the
  fixed shape over free-form composable passes. Endorse strongly.
- **Strategies-as-presets turns the switch into a visible table.** The §5
  mapping is the right shape and is immediately readable.
- **The `bins_generated` disagreement was caught** and correctly flagged with
  the superset lean. My grep confirms only `merge_subsys` names it from outside
  the plugin internals, so the superset choice (`[early,generated,run_all]`) is
  low-risk if `merge_subsys`'s BINS path is the only consumer.
- **`resolve_helpers`-as-preset is the right payoff story**, and the
  `bypass → [report,guard]` move into `files/_bin` (the actual bypass consumer)
  is principled: the mechanism contributes a layer, like any subsystem.
- **The staged plan's load-bearing order** (D→E→F→G) is genuinely load-bearing;
  E depends on D, F depends on D, G depends on D+E.

## Bottom line for the next round

Fix the draft's evidence base before its staging: fold the lookup plugin
(`merge_subsys.py` + `ARTIFACT_DEFAULTS`) and the shims (`mergeKeyed.py`,
`listify.py`) into the duplication map and stage G; note the two `_merge_keyed`
copies are not behaviorally equivalent (tag preservation); resolve the `helpers:
False` nuclear opt-out in the §6 preset; give `replace` a type-agnostic slot;
and either delete or explicitly defer the dead `subsystem_*` profiles. With
those, the pipeline thesis stands and the plan is executable.
