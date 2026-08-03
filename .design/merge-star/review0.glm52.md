---
type: Review
title: "review0 — merge-star draft0"
description: Critical review of draft0. Grounds every load-bearing claim against the current source, then surfaces what the draft omits or misstates — a third merge_keyed surface (mergeKeyed.py), the tag-preservation asymmetry between the two _merge_keyed copies, the bins_generated shape mismatch, the arrayitize count, the _deep_merge_dicts gap, and a bug in the proposed arrayitize→merge_list migration recipe — before giving leans on the draft's own open questions and the staging risks.
resource: /home/rektide/src/compfuzor/.design/merge-star/review0.glm52.md
tags: [compfuzor, merge, pipeline, architecture, review]
status: draft
generated: { by: llm:glm52, at: 2026-08-02T00:00:00Z }
sources:
  - id: draft0
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft0.md
    title: draft0 — the design under review
  - id: merge-py
    resource: /home/rektide/src/compfuzor/library/filter_plugins/merge.py
    title: merge.py — merge_list/merge_dict/_merge_keyed/_collect_payloads/subsys_publish
  - id: merge-strategy-py
    resource: /home/rektide/src/compfuzor/library/filter_plugins/merge_strategy.py
    title: merge_strategy.py — merge_with_strategy + duplicate _merge_keyed
  - id: helpers-py
    resource: /home/rektide/src/compfuzor/library/filter_plugins/helpers.py
    title: helpers.py — resolve_helpers (the preset-to-be)
  - id: arrayitize-py
    resource: /home/rektide/src/compfuzor/library/filter_plugins/arrayitize.py
    title: arrayitize.py — the redundant normalizer
  - id: mergeKeyed-py
    resource: /home/rektide/src/compfuzor/library/filter_plugins/mergeKeyed.py
    title: mergeKeyed.py — compat-shim filter NOT mentioned in draft0
  - id: bin-helpers-init
    resource: /home/rektide/src/compfuzor/.design/bin-helpers/init.glm52.md
    title: prior wave — bin helpers decomposition
---

# review0 — merge-star draft0

## 0. What this is

`draft0` ([`.design/merge-star/draft0.md`](/home/rektide/src/compfuzor/.design/merge-star/draft0.md))
proposes collapsing the merge family (`merge.py` + `merge_strategy.py` +
helpers glue) onto **one fixed-shape pipeline** — `collect → combine →
refine → extract` — with bounded registered vocabularies at the two
pluggable stages, so that every existing "strategy" becomes a named preset
`(combine, refine[])` and `resolve_helpers` stops being special.

This review does two things:

1. **Grounds the draft's claims against the current source.** The draft's
   duplication map and staging are load-bearing; several of their factual
   premises don't quite match the code, and the mismatches change what the
   plan has to do.
2. **Surfaces what the draft leaves out** — one whole filter surface, one
   combine semantic the vocabulary can't express, one classification error,
   and a bug in the migration recipe — then gives leans on the draft's own
   §9 open list.

The thesis (fixed shape, strategies-as-presets, combine-one / refine-list)
is sound. The maps in §3–§5 are the right shape. The problems are in the
*inventory*: the draft undercounts the surfaces it has to unify and
overstates how mechanical two of the migrations are.

> **Research prompt (if this were handed off fresh):** "In
> `/home/rektide/src/compfuzor/library/filter_plugins/`, enumerate every
> public filter and internal helper that performs keyed-record merge,
> list-normalization, or layered dict union; for each, record its caller
> shape, its skip/None semantics, and whether it preserves Ansible
> datatags on string concat. Goal: confirm the closed vocabulary in
> `draft0` §4 is actually exhaustive before staging."

## 1. Verdict

**Direction: accept.** The fixed-shape pipeline is the right frame and the
combine/refine split is well argued. **Maps: needs revision** — the
duplication map misses a third surface, miscategorizes one strategy, and
understates two semantic divergences. **Staging: mostly right order, but
Stage D's exit criteria don't guarantee what they claim, Stage F's recipe
has a bug, and Stage H is bigger than "optional."** Details below.

## 2. Strengths (so they don't get lost in critique)

- **The combine-one / refine-list distinction is the strongest move.**
  Recasting `append_unique` as `(concat, [dedupe])` and
  `append_unique_by` as `(concat, [dedupe_by])` makes the
  relationship-between-strategies visible without a switch — exactly the
  "bounded design space" promise. §3 delivers on this.
- **Correctly identifies the real latent bug.** The `bins_generated`
  disagreement is genuine (see §3.4 below for *how* genuine). Flagging it
  as "defined twice, disagree" is right; it's a live divergence, not
  theoretical.
- **`resolve_helpers` is already half-migrated, which de-risks Stage D.**
  The code already expresses `bypass → [report,guard]` as a *layer append*
  ([`helpers.py:78-80`](/library/filter_plugins/helpers.py)), not a merge
  switch branch — exactly the "contribute a layer" pattern the draft wants
  for `files/_bin`. Only `implicate` (`report → loud`,
  [`helpers.py:84-86`](/library/filter_plugins/helpers.py)) and
  `canonicalize` (`[h for h in HELPERS …]`,
  [`helpers.py:89`](/library/filter_plugins/helpers.py)) remain as
  hardcoded post-steps. So Stage D is "extract two refines + move one
  layer," not "rewrite the resolver." Smaller than it reads.
- **§9 "explicitly open for critique" is good discipline.** This review
  answers it in §6.

## 3. Grounding errors — the draft's inventory is incomplete

These are ordered by how much they change the plan.

### 3.1 `mergeKeyed.py` is a third surface the duplication map never mentions

There is a public filter `mergeKeyed` at
[`library/filter_plugins/mergeKeyed.py:11`](/library/filter_plugins/mergeKeyed.py)
— a compat shim that wraps `merge_with_strategy` with `{op: merge_keyed}`
into a `items:` field. It is a *third* `merge_keyed` surface on top of the
two `_merge_keyed` copies the draft's §2 table rows over.

This matters for the draft's own exit criteria:

- Stage D says "one `_merge_keyed`." Fine — but `mergeKeyed` is a caller of
  `merge_with_strategy`, which calls `merge_strategy._merge_keyed`
  ([`merge_strategy.py:159`](/library/filter_plugins/merge_strategy.py)).
  It is not touched by "delete the duplicate." It is touched only
  *transitively* once Stage E lands.
- Stage G says "single source of truth for every named strategy/profile."
  `mergeKeyed` has no profile entry — it's an ad-hoc shim. Its fate
  (keep as thin compat over the pipeline? retire? who calls it?) is
  unstaged.

**Action for draft1:** add `mergeKeyed.py` to the §2 duplication map as a
third row, and add an explicit step to Stage E or G for it. Suggested
exit-criterion addition: *"no `merge_keyed` code path exists outside the
one registered `keyed_fold` combine; `mergeKeyed` filter (if kept) is a
one-line preset dispatch."*

### 3.2 The two `_merge_keyed` are *not* "byte-near-identical"

The duplication map ([draft0 §2](/home/rektide/src/compfuzor/.design/merge-star/draft0.md))
calls them "byte-near-identical." They are not. On `concat_fields` string
overlap:

- [`merge.py:_merge_keyed`](/library/filter_plugins/merge.py) calls
  `_concat_strings_preserving_tags` → `AnsibleTagHelper.tag_copy`
  ([`merge.py:296`](/library/filter_plugins/merge.py)), preserving
  source-location datatags across the join.
- [`merge_strategy._merge_keyed`](/library/filter_plugins/merge_strategy.py)
  does bare `existing + "\n" + value`
  ([`merge_strategy.py:46`](/library/filter_plugins/merge_strategy.py)) —
  **drops tags**.

So "delete one, keep the other" is a *semantic decision*, not a
deduplication. Which behavior wins for `merge_with_strategy`'s callers
(notably `mergeKeyed` → BINS `generated` concat)? The draft doesn't say.
Picking the tag-preserving version is almost certainly correct (it's why
`_raw_copy_template_data` exists throughout `merge.py`), but it should be
a **stated decision**, with the call sites that currently get untagged
output checked for reliance on the old behavior.

**Action:** replace "byte-near-identical" with the real diff, and make the
tag-preservation choice an explicit Stage D/E decision with a test.

### 3.3 `bins_generated` is a *shape* mismatch, not a `concat_fields` disagreement

The draft frames the `bins_generated` bug as two definitions disagreeing
on `concat_fields` (`[early, generated, run_all]` vs `[generated]`). That
undersells it. The two definitions are **different shapes consumed by
different entry points**:

- [`merge.py:49`](/library/filter_plugins/merge.py): a *list-strategy
  profile* — `{op: merge_keyed, key: name, concat_fields: [...]}` — fed to
  `merge_list('bins_generated')`.
- [`merge_strategy.py:82`](/library/filter_plugins/merge_strategy.py): a
  *strategy-map profile* — `{"BINS": {op, key, concat_fields}}` — fed to
  `merge_with_strategy(_, 'bins_generated')`.

So Stage E step 3 ("pick one `concat_fields`") doesn't actually unify them
— you'd still have one shape for `merge_list` and another for
`merge_with_strategy`. Stage G's promise that
`merge_list('bins_generated')` and
`merge_with_strategy(records, 'bins_generated')` "resolve to the *same*
definition" requires a **profile model that spans both entry points**,
which is a harder design than "pick the superset." It implies either (a)
profiles are entry-point-agnostic and each entry point projects them, or
(b) one entry point is demoted to sugar over the other.

**Action:** promote this from an open note to a Stage G design question
with the two options sketched. My lean: (a) — a profile is a named
`{kind: list|map, combine, refine, …}` record; each entry point validates
and projects. It keeps `merge_list`/`merge_dict` as honest entry points
while making the name the single source of truth.

### 3.4 `replace` is mis-filed as a dict combine

In §4 the draft files `replace` under "Dict combines." But `replace` in
`merge_with_strategy` is **type-polymorphic** — it's "last non-None
payload wins wholesale," applied per-field regardless of whether the value
is a dict, list, or scalar
([`merge_strategy.py:301-304`](/library/filter_plugins/merge_strategy.py);
the initial value is `None`
([`merge_strategy.py:144`](/library/filter_plugins/merge_strategy.py)),
not `{}` or `[]`). It's the one strategy that doesn't care about payload
type.

Putting it in the dict table is a category error that the list/dict split
can't accommodate. This is the canary for §3.4's deeper issue (next
section): **the combine vocabulary doesn't actually split cleanly on
type.**

**Action:** give `replace` its own row as a *type-agnostic* combine, or
introduce a "scalar/any" combine group. The current two-table layout
implies a type discipline the vocabulary doesn't have.

### 3.5 `_deep_merge_dicts` / `subsys_publish` is outside the proposed vocabulary

`subsys_publish` does not use `union`/`overlay`. It calls
`_deep_merge_dicts`
([`merge.py:719,725`](/library/filter_plugins/merge.py)) — a **recursive
deep merge** (dicts fold recursively, non-dicts overwrite). None of
`concat / keyed_fold / union / replace` expresses this. The proposed
combine vocabulary has no `deep_union`.

Stage H waves at this ("verify they ride it naturally"). They don't, not
without a fifth combine. So either:

- register `deep_union` as a combine (and decide its `concat_fields`
  analogue — there is none, it's recursive by default), **or**
- concede `subsys_publish` is a different beast (a publish/mutate op, not
  a merge) and explicitly scope it *out* of the pipeline.

The draft can pick either, but "verify they ride it naturally" is the
wrong verb — they won't. Stage H is not optional if the goal is "the merge
family collapses onto the pipeline," because `subsys_publish` + the
`merge_*_subsys` family are half of `merge.py`'s public surface
([`merge.py:735-743`](/library/filter_plugins/merge.py)).

**Action:** make Stage H non-optional and record the decision (new combine
vs. explicit exclusion). My lean: **exclusion.** `subsys_publish` mutates
a context global (`SUBSYSTEM`) and does a deep merge to avoid clobbering
nested contributions — that's a *publish* semantic, not a *merge*
semantic. Forcing it into the pipeline muddies both. Say so.

### 3.6 The `arrayitize` count is wrong, and so is the migration scope

- The draft says "50 call sites" (§1, Stage F). Reality:
  `rg -o arrayitize` → **121 token hits**; `rg -c '\| arrayitize' --type yaml`
  → **37 pipe-form Jinja call sites** (the ones that actually migrate).
  Neither is 50. The number needs a real count before Stage F is sized.
- There is also a **Python-internal copy** `_arrayitize` at
  [`bin_composers.py:23`](/library/filter_plugins/bin_composers.py), used
  at [`bin_composers.py:81,94`](/library/filter_plugins/bin_composers.py)
  — *not* a Jinja site, so it doesn't migrate via `X | merge_list`. Stage
  F step 2 (delete the copy) is fine, but its replacement is a Python
  import of `_as_list`, not a filter swap. Worth saying so Stage F doesn't
  get attempted as a sed over templates.

### 3.7 The Stage F migration recipe (`single=True`) is subtly wrong

Stage F says most sites become `X | merge_list(single=True)`. Tracing
`_collect_payloads` ([`merge.py:425`](/library/filter_plugins/merge.py))
against `arrayitize` ([`arrayitize.py`](/library/filter_plugins/arrayitize.py)):

| input `X` | `X \| arrayitize` | `X \| merge_list(single=True)` (default `skip='none,undefined'`) | match? |
|---|---|---|---|
| `[a,b]` | `[a,b]` (spreads) | `[a,b]` (one payload, then `concat` flattens via `_as_list`) | ✅ |
| `'foo'` | `['foo']` | `['foo']` | ✅ |
| `False` | `[]` ([`arrayitize.py:16`](/library/filter_plugins/arrayitize.py)) | `[False]` — **not skipped** by default | ❌ |
| `None` | `[]` | `[]` (skipped by default) | ✅ |

So `single=True` is the right flag (good — it matches the spread vs wrap
behavior), **but the default `skip` does not reproduce `arrayitize`'s
`False → []` rule.** Sites that pipe a possibly-`False` value (and there
are some — the `default([])` idiom in
[`vars/common.yaml`](/vars/common.yaml) papers over many, but not all)
will silently change behavior to `[False]` unless the migration adds
`skip='false,none,undefined'` or equivalent.

The draft's §1 explicitly celebrates the `skip=` kwarg as the mechanism
for the `base_helpers: False` convention — and then Stage F forgets to
apply it. This is exactly the kind of "mechanical migration" bug the
pipeline is supposed to prevent.

**Action:** Stage F's recipe must specify the skip policy per-site (or
default to `skip='false,none,undefined'` for the `as_list` alias). Add an
exit criterion: *"no migrated site changes behavior on `False`/`None`
input."* A test matrix over `{list, scalar, False, None, undefined}` for
both old and new is cheap and catches this.

## 4. Conceptual gap — the list/dict combine split is leaky

§3.4 (`replace`) is one symptom. The broader issue: the draft's §4 combine
tables assert a list/dict partition, but the vocabulary doesn't honor it.

- `concat` — lists only.
- `keyed_fold` — **lists of dicts** (it's a list combine that folds dict
  records). Already straddles.
- `union` — dicts only.
- `replace` — any type (§3.4).

So `keyed_fold` lives in the list table but operates on dict records, and
`replace` lives in the dict table but is type-agnostic. The partition is
decorative. This is the real content of the draft's own §9 question "one
pipeline vs two entry points" — and the answer the tables implicitly give
("two, by type") is contradicted by the tables themselves.

**Lean:** keep two *entry points* (`merge_list` / `merge_dict`) for
back-compat and because the call sites are shaped differently, but stop
pretending the combine vocabulary partitions by type. Instead, partition
combines by **what they fold over**: list-of-scalars (`concat`),
list-of-records (`keyed_fold`), dict (`union`), anything (`replace`).
Entry-point validation then checks "does this combine apply to this payload
shape?" rather than "is this the list table or the dict table?" That makes
the `merge_list('bins_generated')` → `keyed_fold` dispatch a payload-shape
check, which is what it actually is.

## 5. Where `dictify` lives — the draft's most under-developed open question

`tool_versions_overlay` runs `dictify` per-payload *before* `union`
([`merge.py:402-406`](/library/filter_plugins/merge.py)). The draft lists
three homes for it (combine-arg, per-payload map in collect, own combine)
and marks "open." This isn't a footnote — it's the test case for whether
`collect` is really just arrayitize or whether it has a per-payload-map
slot, and whether combines are allowed pre-transforms.

**Lean:** per-payload map in `collect`. Reasons:

1. It keeps combines pure (`(payloads) → value`), matching the contract in
   §4 Stage 2. Letting combines take pre-transforms is the slippery slope
   back to "a combine is a list of ops" the draft explicitly rejects in
   §9.
2. `dictify` is shape normalization, exactly analogous to
   `_as_list`/`_as_dict` — it belongs with the gathering step, not the
   fold.
3. It generalizes: any future "parse-then-merge" profile
   (`tool_versions_overlay` is surely not the last) gets the same hook.

Cost: `collect` grows a `map=` kwarg. Acceptable — it's still mechanism,
not policy.

## 6. Leans on draft0 §9's own open questions

| §9 question | draft's lean | my lean | why |
|---|---|---|---|
| slot names | `collect/combine/refine/extract` | **agree** | `gather→fold→shape→pick` reads as transforms; the draft's names read as *roles*, which is what you want when reasoning about a preset. Keep. |
| combine-one vs refine-list | keep split | **agree, hard** | this is the thesis; do not fold refine into combine. The "one core op + optional polish" clarity is the whole payoff. |
| `dedupe_by` residence | refine (open) | **refine** | `concat + dedupe_by` composing is exactly what makes `append_unique_by` legible as a preset. The current code files it as a combine-*op* ([`merge.py:313`](/library/filter_plugins/merge.py)) and that's the bug, not a preference. |
| `keyed_fold` residence | combine (open) | **combine** | a per-field fold with `concat_fields` is not a post-process on a concatenated list; it needs pairwise record merging. Refine only sees the combined value. |
| one vs two entry points | two (open) | **two entry points, no type-partition** (see §4) | keep `merge_list`/`merge_dict` for call-site shape; drop the pretend type-split in the vocab. |
| `dictify` home | open | **per-payload map in collect** (see §5) | |
| profile registry location/shape | open | **one registry, profile = `{kind, combine, refine, …}`, entry points project** (see §3.3) | this is the only way Stage G's "same definition" promise holds. |
| `skip` as its own stage | keep folded | **agree** | it filters *during* gather; promoting it adds a stage that's empty for every preset that isn't `resolve_helpers`. Not worth it. |

## 7. Staging risks the exit criteria don't cover

- **Stage D exit criterion "no strategy switch remains" is too weak.** It's
  trivially satisfiable while `merge_strategy.py` still has its own
  dispatch (you could "register" combines and still branch on them).
  Stronger: *"the only place a strategy name is interpreted is the preset
  table lookup."* That's the actual invariant.
- **Stage D doesn't sequence the `mergeKeyed.py` caller.** See §3.1.
  `mergeKeyed` → `merge_with_strategy` → `_merge_keyed` means Stage D's
  "one `_merge_keyed`" isn't reachable until Stage E rewrites
  `merge_with_strategy`. Either reorder (E before D's `_merge_keyed`
  consolidation) or split D into D1 (vocab registration) and D2 (delete
  the duplicate, post-E).
- **No stage owns the `_positional_strategy` back-compat shim.** §8 lists
  it under "cleanup" but it's load-bearing for the 37+ pipe-form callers
  (`X | merge_list('append_unique')`). Migrating those to `strategy=` is
  its own staged step with its own exit criterion, or the shim is
  permanent. State which.
- **Stage F's "decide arrayitize.py's fate" should be decided now**, not
  deferred. A thin compat shim over `_collect_payloads` is strictly better
  than removal for a 37-site migration (do the rename, leave the alias,
  retire later). Deferring keeps the migration blocked on a non-decision.
- **Validation collapse (§8 last bullet) needs to be a stage, not a note.**
  `_validate_list_strategy` / `_validate_dict_strategy` /
  `_validate_strategies` are three validators with overlapping but
  *different* valid sets (note `dict_overlay` is valid for dict but
  `overlay` is the canonical name; `replace` is valid only in
  `merge_strategy`). Unifying them is a behavior change, not a refactor —
  it belongs in the staging with its own exit criterion and test.

## 8. Characterization & what draft1 needs

`draft0` is a **strong thesis with a leaky inventory.** The architecture
is right; the parts list isn't. Specifically it (a) misses a public
filter (`mergeKeyed`), (b) calls two divergent functions identical (the
`_merge_keyed` tag asymmetry), (c) frames a shape problem as a value
problem (`bins_generated`), (d) mis-shelves one strategy (`replace`),
(e) can't express one public merge (`_deep_merge_dicts`), and (f) ships a
migration recipe with a `False`-handling bug. None of these sink the
design — they're the normal gap between a draft and a buildable plan. But
each one is the kind of thing that becomes a real bug under "stages are
intended, order is load-bearing."

**For draft1:**

1. Fix the duplication map: three rows for `merge_keyed` (`merge.py`,
   `merge_strategy.py`, `mergeKeyed.py`), with the tag-preservation diff
   called out as a decision.
2. Re-draw `bins_generated` as a shape-unification problem with the
   profile-model sketch from §3.3.
3. Add `replace` as type-agnostic and drop the pretense that combines
   partition by type (§4).
4. Decide Stage H (`deep_union` combine vs. explicit exclusion of
   `subsys_publish`); make it non-optional.
4. Correct the `arrayitize` count and fix the Stage F recipe
   (`skip=` policy, `single=` rationale, Python copy handled separately).
5. Tighten exit criteria to invariants ("only the preset table interprets
   strategy names") and add the missing owners (`mergeKeyed`,
   `_positional_strategy`, validator collapse).
6. Fold §5/§6 leans into the body — the open questions are mostly
   answerable now, and a draft that commits is more useful than one that
   hedges.

The result should be a plan where every public merge surface in
[`merge.py`](/library/filter_plugins/merge.py),
[`merge_strategy.py`](/library/filter_plugins/merge_strategy.py),
[`mergeKeyed.py`](/library/filter_plugins/mergeKeyed.py),
[`arrayitize.py`](/library/filter_plugins/arrayitize.py), and
[`helpers.py`](/library/filter_plugins/helpers.py) is explicitly accounted
for as either "becomes a preset," "becomes a combine/refine," "becomes a
compat alias," or "explicitly excluded." That's the bar for "the merge
family collapses onto it."

## 9. References

- [`draft0.md`](/home/rektide/src/compfuzor/.design/merge-star/draft0.md) — the design under review
- [`merge.py`](/home/rektide/src/compfuzor/library/filter_plugins/merge.py) — `_merge_keyed:259`, `_concat_strings_preserving_tags:242`/`:296`, `_append_unique_by:313`, `_collect_payloads:425`, `_positional_strategy:411`, `subsys_publish:692`, `_deep_merge_dicts:725`
- [`merge_strategy.py`](/home/rektide/src/compfuzor/library/filter_plugins/merge_strategy.py) — duplicate `_merge_keyed:16` (untagged string concat `:46`), `bins_generated` profile `:82`, `replace` strategy `:301`
- [`mergeKeyed.py`](/home/rektide/src/compfuzor/library/filter_plugins/mergeKeyed.py) — the compat-shim filter omitted from draft0's map
- [`helpers.py`](/home/rektide/src/compfuzor/library/filter_plugins/helpers.py) — `resolve_helpers:40`, bypass-as-layer `:78`, `report→loud` implicate `:84`, canonicalize `:89`
- [`arrayitize.py`](/home/rektide/src/compfuzor/library/filter_plugins/arrayitize.py) — `_normalize_single:15` (`False→[]` rule `:16`)
- [`bin_composers.py`](/home/rektide/src/compfuzor/library/filter_plugins/bin_composers.py) — Python-internal `_arrayitize:23` (callers `:81`,`:94`)
- [`bin-helpers/init.glm52.md`](/home/rektide/src/compfuzor/.design/bin-helpers/init.glm52.md) — prior wave; confirms the bypass-as-layer pattern is already in place
