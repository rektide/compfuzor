---
type: Synthesis
title: "draft1-syn0 — merge-star: four drafts that agreed on almost everything"
description: Synthesis of the four draft1 waves (glm52, ds4f, gpt56t, m3). The wave converged unusually hard: 13 decisions are unanimous and carry forward as the contract. 10 real tensions remain, almost all on the "how hardline do we apply P2?" axis. This syn takes a position on each, assembles a best-of canonical draft1 from the strongest section of each source, flags two questions for the human, and cross-compares the four drafts. Notable findings: ds4f caught that listify is not a normalizer duplicate (only listify.concat is) and that arrayitize silently drops True/False — both verified; glm52 and m3 said "exact contract" without noticing the bool-drop, which is the wave's one shared factual miss. The single most load-bearing open question is dedupe identity (str(value) vs equality): three of four say keep-and-document, one says fix; the syn defers it to the human.
resource: /home/rektide/src/compfuzor/.design/merge-star/draft1-syn0.glm52.md
tags: [compfuzor, merge, pipeline, architecture, synthesis]
status: draft
generated: { by: llm:glm52, at: 2026-08-03T00:00:00Z }
sources:
  - id: draft1-glm52
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft1.glm52.md
    title: draft1.glm52 — fixed pipeline, no back-compat, explicit signals
  - id: draft1-ds4f
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft1.ds4f.md
    title: draft1.ds4f — fixed-step pluggable pipeline, consistency-first
  - id: draft1-gpt56t
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft1.gpt56t.md
    title: draft1.gpt56t — explicit layers, explicit presets, no compatibility surface
  - id: draft1-m3
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft1.m3.md
    title: draft1.m3 — explicit pipeline, no shims
  - id: prior-syn
    resource: /home/rektide/src/compfuzor/.design/merge-star/review0-syn0.glm52.md
    title: review0-syn0 — the prior synthesis (D1–D5)
  - id: merge-subsys-lookup
    resource: /home/rektide/src/compfuzor/library/lookup_plugins/merge_subsys.py
    title: merge_subsys.py — ARTIFACT_DEFAULTS (the live consumer)
---

# draft1-syn0 — merge-star: four drafts that agreed on almost everything

## 0. The morale reframe (read this first)

The review wave produced 25 findings; this wave produced **four drafts that
agree on 13 of 23 decisions**. That is an unusually hard convergence. The
explanation is structural: the human set P2 ("consistency wins, no shims")
explicitly between the waves, and that single instruction dissolved the
items the prior syn had hedged on (`_positional_strategy` bless-vs-migrate,
`dict_overlay` alias, `arrayitize` retirement). What remains is small:

```mermaid
flowchart LR
  subgraph settled["13 unanimous decisions — the contract"]
    C1["fixed shape<br/>collect→combine→refine→extract"]
    C2["P2 no-shims"]
    C3["3-class skip<br/>absence|suppress|nuclear"]
    C4["false = v is False<br/>verified distinguishable"]
    C5["folds-over grouping"]
    C6["dictify_union"]
    C7["one tag-preserving<br/>keyed_fold"]
    C8["two registries<br/>VALUE_PRESETS + FIELD_PROFILES"]
    C9["ARTIFACT_DEFAULTS<br/>= live projection"]
    C10["bins_generated superset"]
    C11["Stage 0 char-tests"]
    C12["dedupe_by → refine<br/>keyed_fold → combine"]
    C13["subsys_publish<br/>excluded"]
  end
  subgraph tensions["10 real tensions — mostly P2 application line"]
    T1["mergeKeyed fate"]
    T2["dedupe identity"]
    T3["no_header alias"]
    T4["listify fate"]
    T5["subsystem_* fate"]
    T6["merge_with_strategy rename"]
    T7["strategy= vs preset="]
    T8["as_list bool handling"]
    T9["implicate cycle policy"]
    T10["empty skip predicate"]
  end
  settled --> tensions
```

**Two things to notice up front:**

1. **The tensions cluster on one axis: how strictly to apply P2.** Every
   divergence is "remove vs keep a named thing." The architecture is
   settled; only the migration's edge cases are live.
2. **One shared factual miss.** glm52 and m3 (me, and the model whose
   framing I most resemble) both said "ship `as_list` with `arrayitize`'s
   exact contract" without noticing that `arrayitize` silently does
   `True/False → []`. ds4f and gpt56t caught it explicitly and rejected
   it under P3/P6. This is the wave's one load-bearing factual error and
   it flips a Stage 0 row.

I flag (2) because the prior syn's lesson — *run the code on any claim
rated difficulty ≥ 0.5* — was not consistently applied inside this wave
either. The syn step is still where verification is cheapest.

## 1. Unanimous decisions (carry forward as contract)

These 13 items appear in all four drafts with no disagreement. They are
the part of draft1 that is settled. Anyone implementing should not
relitigate them.

| # | decision | notes |
|---|---|---|
| C1 | fixed shape: `collect → combine → refine[] → extract` | draft0's thesis; the wave ratified it |
| C2 | P2 — no back-compat shims, migrate callers | human-set; reversed syn0's "bless the shim" |
| C3 | three operation classes: absence / suppress / nuclear | nuclear is **caller-side guard**, never a skip predicate |
| C4 | `false` predicate = `v is False` (strict identity); distinguishable from `[False]` and from `False` inside a list-layer | verified by all four against `_collect_payloads` |
| C5 | combines grouped by *folds-over* (list-scalar / list-record / dict / any), not list-vs-dict | drops draft0's decorative split |
| C6 | `dictify_union` is a named combine; no `collect.map=` slot | D3 from syn0, ratified |
| C7 | one `keyed_fold`, the tag-preserving version | `merge.py`'s survives; `merge_strategy.py`'s deleted as a fix |
| C8 | two registries: `VALUE_PRESETS` + `FIELD_PROFILES` | a field-profile references value-presets; never redefines |
| C9 | `ARTIFACT_DEFAULTS` is the live projection; promoted, not replaced | ds4f's catch from review0; all four now carry it |
| C10 | `bins_generated` resolves to the superset `concat_fields=[early,generated,run_all]` | low-risk; only `merge_subsys` names it live |
| C11 | Stage 0 = characterization tests, gates all extraction | gpt56t's matrix from review0; all four adopt |
| C12 | `dedupe_by` → refine; `keyed_fold` → combine | draft0 §9, ratified |
| C13 | `subsys_publish` + `_deep_merge_dicts` explicitly excluded from pipeline | publish/mutate, not merge |

If you read only this table, you have the architecture. The rest is
naming, migration sizing, and edge-case policy.

## 2. Tensions — where the four diverge

Every tension is "how hardline does P2 apply to *this specific named
thing*?" The principle is clear in direction; the *line* is judgment.

### T1 — `mergeKeyed.py` fate (named public filter)

| draft | position |
|---|---|
| glm52 | retire (P2); 2 callers migrate to `merge_list(strategy='merge_keyed')` |
| ds4f | **keep** as one-line field-profile dispatch; public name preserved |
| gpt56t | **delete** entirely; callers use `merge_list(preset=...)` |
| m3 | **keep**; named machinery, not a shim; transparent refactor |

The split: gpt56t treats `mergeKeyed` as compat machinery; ds4f+m3 treat
it as a named public filter with real callers. glm52 split the difference
toward removal.

### T2 — `dedupe` identity (`str(value)` vs equality)

| draft | position |
|---|---|
| glm52 | **fix to equality** (P2 — the wart is real, `[1,"1"]` collapses) |
| ds4f | keep and document (equality on unhashable dicts needs a canonical key; real work for zero breakage) |
| gpt56t | keep and document ("retain and document current `str(value)` identity in this work") |
| m3 | keep and document ("existing behavior — kept under the principle, not changed") |

Three-to-one for keep-and-document. The one (glm52, me) is arguing from
principle consistency; the three are arguing from "the fix has a real
implementation surface (canonical-key helper for unhashable values) for
zero current breakage." Both sides are honest.

### T3 — `no_header` legacy alias

| draft | position |
|---|---|
| glm52 | (does not explicitly remove; silent on it) |
| ds4f | **remove** (3 sites migrate to `helpers: False`) |
| gpt56t | (does not address directly) |
| m3 | **remove** (Stage D; `files/*` callers migrate) |

Two-to-none explicit (glm52 and gpt56t are silent, not opposed). ds4f
sized it precisely: 3 sites (`pw-surround.etc.pb:38,46`,
`vars_systemd_unit.tasks:208`).

### T4 — `listify` fate

| draft | position |
|---|---|
| glm52 | retire (with `concat`) |
| ds4f | **keep `listify`, retire only `listify.concat`** — `listify.py:10-11` is a dict→list-of-{key,value} transform, not a normalizer |
| gpt56t | retire entirely |
| m3 | retire |

ds4f is the **only** draft that read `listify.py:10-11`. The other three
called it a normalizer duplicate without checking. ds4f's catch flips
this: listify-the-filter is a distinct shape-transform; only its
`concat` alias is redundant.

### T5 — `subsystem_contrib` / `subsystem_artifacts` fate

| draft | position |
|---|---|
| glm52 | re-derive from ARTIFACT_DEFAULTS (lean; preserves documented public API) |
| ds4f | re-derive (preserve README/arch.md surface) |
| gpt56t | **remove** — no internal playbook caller justifies a second global profile registry; docs migrate to explicit profiles |
| m3 | re-derive as named bundles |

Three-to-one for re-derive. gpt56t is the strictest read; the other
three weight the documented public API more.

### T6 — `merge_with_strategy` rename to `merge_fields`

| draft | position |
|---|---|
| glm52 | keep the name; reimplement as field-profile dispatch |
| ds4f | keep the name; keep `into`/`single`/`aggregate`/`payload_path` in the adapter (record-level collect analog) |
| gpt56t | **rename to `merge_fields`**; drop record-gathering options; callers prepare records |
| m3 | keep the name |

Three-to-one for keep-the-name. gpt56t's "callers prepare records"
sub-point has merit — the record-gathering kwargs are a collect-analog
that leaks into the field-dispatch layer.

### T7 — `strategy=` vs `preset=` keyword

| draft | position |
|---|---|
| glm52, ds4f, m3 | `strategy=` (existing term) |
| gpt56t | **`preset=`** (rename; emphasizes the registry semantics) |

Three-to-one for the existing term. gpt56t's rename is aesthetic; the
principle doesn't require it.

### T8 — `as_list` boolean handling (the wave's one factual miss)

| draft | position |
|---|---|
| glm52 | "`arrayitize`'s exact contract" — *misses that arrayitize does `True/False → []`* |
| ds4f | **strict**: `False`/`True` are data → `[False]`/`[True]`; explicitly rejects arrayitize's silent drop under P3/P6 |
| gpt56t | **strict**: `as_list(any scalar, including False, True, 0, …) → [value]` |
| m3 | "`arrayitize`'s exact contract" — *misses the bool-drop* |

glm52 (me) and m3 said "exact contract" without checking. ds4f and
gpt56t read `arrayitize.py:16` and noticed it silently drops booleans.
Under P3 ("`False` is an explicit signal") and the verified skip
contract, `as_list(False) = [False]`, not `[]`. **The strict contract
wins.** This is the wave's one shared factual error and it flips a
Stage 0 row.

### T9 — `implicate` cycle policy

| draft | position |
|---|---|
| glm52, m3, gpt56t | cycle ⇒ error |
| ds4f | cycle ⇒ error *might* break a playbook that resolves cyclically by accident; cycle⇒ignore may be safer — flag for Stage 0 verification |

ds4f's worry is real but unverified. Three-to-one for error, with the
caveat that Stage 0 should reveal if any live playbook resolves
cyclically today.

### T10 — `empty` skip predicate

| draft | position |
|---|---|
| ds4f | keep; drop if Stage 0 shows no caller (flagged tension) |
| others | vary; mostly silent |

Low-stakes. Decide from evidence in Stage 0.

## 3. Resolution table — my lean on each tension

I amglm52, the same model that wrote `draft1.glm52.md` and the prior
syn. I'm going to try to be fair to the three other drafts, including
where they're more correct than mine. Where I flip my own draft's
position, I say so.

| # | tension | syn lean | winner | why | flips my draft? |
|---|---|---|---|---|---|
| T1 | `mergeKeyed.py` fate | **keep as one-line dispatch** | ds4f + m3 | named public filter with real callers; "thin dispatch under stable name" is consistent without being a hack. P2 removes *shims and aliases*; named public filters are features. | **yes** — glm52 said retire |
| T2 | `dedupe` identity | **defer to human (Q1)** | split | the strongest argument (glm52, from principle) collides with the most honest counter-argument (ds4f: real canonical-key work for zero breakage). Three-to-one is not enough to override the one being principled. Flag it. | no |
| T3 | `no_header` alias | **remove** | ds4f + m3 | 3 sites is bounded; dual-spelling is exactly what P2 kills. | **partially** — glm52 was silent, should have said remove |
| T4 | `listify` fate | **keep listify; retire only `listify.concat`** | ds4f alone | ds4f is the only one that read `listify.py:10-11`. The dict→list-of-{key,value} transform is real and distinct. | **yes** — glm52 said retire |
| T5 | `subsystem_*` fate | **re-derive** | glm52 + ds4f + m3 | three-to-one; preserves documented public API; gpt56t's "no internal caller" is true but the README surface is real | no |
| T6 | `merge_with_strategy` rename | **keep the name; move record-gathering to caller** | gpt56t's sub-point + others' name | gpt56t's "callers prepare records" is correct and orthogonal to the rename. Keep the name, adopt the record-gathering cleanup. | **partially** — glm52 should have called out the record-gathering leak |
| T7 | `strategy=` vs `preset=` | **`strategy=`** | glm52 + ds4f + m3 | existing term; rename is aesthetic; P2 doesn't require it | no |
| T8 | `as_list` boolean handling | **strict: `False` is data** | ds4f + gpt56t | verified from `arrayitize.py:16`; required by P3/P6 consistency | **yes** — glm52 said "exact contract" without checking |
| T9 | `implicate` cycle policy | **cycle ⇒ error, with Stage 0 verification** | glm52 + m3 + gpt56t | three-to-one; adopt ds4f's Stage 0 verification as the guard | no |
| T10 | `empty` skip predicate | **drop if Stage 0 shows no caller** | ds4f | decide from evidence | no |

**Five of ten tensions flip my own draft's position.** That is the syn
step doing its job: my draft was the most aggressive on removals, and
the wave's evidence pulled three of those back (mergeKeyed, listify,
as_list contract) and clarified two others (no_header, record-gathering).
I'm reporting the flips rather than hiding them because the syn's
authority comes from citing which draft caught what.

## 4. The canonical draft1 — best-of assembly

Rather than re-write a full draft, here is the assembly map: which
source to lift each section from, with the integrative edits the
resolution table requires.

| section | lift from | integrative edits |
|---|---|---|
| **§1 guiding principles** | m3 | m3's "consistency wins" framing is the cleanest — one principle, applied. Add glm52's P3 ("explicit signals") and P4 ("tests before extraction") as sub-lemmas; m3 underweighted them. |
| **§2 duplication map** | ds4f | ds4f's table is the most precise (exact line numbers, every surface named). Add m3's correction: listify is a shape-transform, not a normalizer dup. |
| **§3 pipeline diagram + stage contracts** | ds4f | ds4f's mermaid + contract table is the tightest on pluggability (mechanism-fixed vs pluggable-one vs pluggable-list). |
| **§4 skip semantics** | glm52 + ds4f | glm52's three-class naming (absence/suppress/nuclear) + ds4f's verified-behavior table (the 4-row `False`-layer vs `[False]`-layer vs inside-list-layer matrix). |
| **§5 combines** | gpt56t | gpt56t's folds-over table is the tightest (combine / layers-accepted / identity / result). Add the `dictify_union` rejection of collect-map from any draft. |
| **§6 refines** | ds4f | ds4f's pinned contracts are the most concrete (dedupe_by asymmetry, implicate spec). Apply T2's deferral: dedupe identity is "documented wart OR fixed to equality — Q1." |
| **§7 registries (VALUE_PRESETS + FIELD_PROFILES)** | ds4f | ds4f's code-block form is the most copyable. Add gpt56t's point: "a field-profile references value-presets; never redefines combine/refine/concat_fields/kind/identity." |
| **§8 preset map** | ds4f | ds4f's per-preset status column (🟡 inline / 🟡 three copies / etc.) is the most useful for migration tracking. |
| **§9 helpers example** | gpt56t + ds4f | gpt56t's `_bin` template snippet is the most concrete (it shows the `helper_layers` construction with bypass). ds4f's "resolve_helpers knows no field names" framing is the cleanest contract. |
| **§10 consistency cleanup (sized)** | ds4f | ds4f's §10 table (10.1–10.6 with exact counts: 14 positional, 3 no_header, 1 dict_overlay, 45 arrayitize, 1 listify.concat, keep listify) is the wave's most precise inventory. **Apply T4: listify stays.** |
| **§11 staging** | glm52 | glm52's Stage 0 → D → E → F → G → H with invariant-based exit criteria is the clearest. Apply T3 (no_header removal in Stage D) and T8 (strict as_list contract in Stage 0). |
| **§12 explicit exclusions** | ds4f | ds4f's "non-goals" list is the most explicit (subsys_publish excluded, free-form passes rejected, deep-union combine not added, polymorphic entry not adopted, collect.map= rejected, as_list strict). |
| **§13 author commentary** | m3 | m3's 10-item self-critique is the model for honest accounting. ds4f's "what I'd want attacked in review" is a useful complement. |

**What the assembly adds that no source had:**

- A single principle (m3) carrying three named sub-lemmas (P3, P4 from
  glm52; gpt56t's "explicit layers" framing as the naming consequence).
- ds4f's exact migration counts grafted onto glm52's staging.
- The strict `as_list` contract (T8) applied retroactively to the
  drafts that missed it.
- The `listify` correction (T4) applied retroactively to the drafts
  that called it a normalizer dup.

## 5. Two questions for the human

These are the only two I'd rather not decide unilaterally:

1. **`dedupe` identity (T2).** The split is 3-keep-and-document vs
   1-fix-to-equality (glm52, me). The principle argument (fix) is
   real; the implementation-cost argument (keep) is also real:
   equality-based dedupe on unhashable dicts needs a canonical-key
   helper, which is its own design question for zero current
   breakage. **My lean as syn, deferring my draft's position: keep
   and document in Stage 0, file the fix as a follow-up ticket.**
   The principle is satisfied by naming the wart loudly, not by
   pretending the fix is free. But this is the one I most want your
   read on.

2. **`subsystem_*` re-derivation projection (m3's §9.6–§9.7).** m3
   caught that `ARTIFACT_DEFAULTS` and `subsystem_contrib`'s field
   sets overlap but are not identical (`ETC_DIRS` is in
   `ARTIFACT_DEFAULTS`, not in `subsystem_contrib`). The
   re-derivation needs a real projection spec, not a hand-wave.
   **Decision needed:** is `subsystem_contrib` a strict subset of
   `ARTIFACT_DEFAULTS` (re-derive as projection), or is it a named
   bundle that happens to overlap (keep as a literal in the
   registry)? This affects Stage G's validator shape.

Everything else the resolution table (§3) takes a lean on; say the
word and either or both of these fold into the canonical draft1.

## 6. Cross-comparison of the four drafts

| draft | strength | most notable contribution | relative weakness | characterization |
|---|---|---|---|---|
| **glm52** | tightest on staging rigor + author self-awareness; explicit P1–P4 principle framing | the morale reframe (skip pushback dissolved the hardest review item); the "no-back-compat" flip on three items; the Stage 0 → H invariant-exit framing | shared the `as_list` bool-drop miss; under-read listify; most aggressive on removals (three flipped back by the wave) | the systems writer: "name the principles, stage the work, cite the wave" |
| **ds4f** | the only one that re-read every filter file before writing; highest single-catch count in this wave | **listify is not a normalizer dup** (`listify.py:10-11` is a dict→list transform) + **arrayitize silently drops True/False** (`arrayitize.py:16`) + exact migration counts (14/3/1/45/1) | kept `dedupe` wart under "pragmatic"; worry about implicate cycles is unverified | the file-reader: "open the source before you claim what it does" |
| **gpt56t** | the most deliberately breaking; tightest combine-table contract; clearest API surface sketch | the `merge_fields` rename proposal (adopt the record-gathering cleanup even if you keep the name); the strict `as_list` contract; the "explicit layers" API shape (`layers` is one sequence, no variadic) | most aggressive on removals that are actually named features (`mergeKeyed` deletion, `subsystem_*` removal); didn't size the migration | the minimalist: "fewer interpretations, even if it costs more migration" |
| **m3** | the most thorough self-critique (10 numbered items); cleanest principle framing (one principle, not four) | the "consistency wins, not throw-away-named-APIs" distinction; the projection-spec catch (`ETC_DIRS` mismatch); the explicit chicken-and-egg on Stage 0 vs Stage D helpers test | shared the `as_list` bool-drop miss; migration count inflated (~120 vs ~64) by counting commit cadence instead of unique sites | the self-critic: "state the principle, then enumerate where your application of it wobbles" |

**Where they agree** is the contract (§1 of this syn). **Where they
disagree** is one axis (P2 application line). **Where they're
complementary:** ds4f's file-reading caught two factual errors the
other three shared; gpt56t's API-shape thinking pushed the others
toward explicitness; glm52's staging made the plan executable; m3's
self-critique surfaced the projection-spec gap.

**The wave's one shared factual error** (T8: glm52 and m3 said "exact
contract" without checking arrayitize's bool-drop) is the most
important process finding: even with the prior syn's explicit lesson
(*run the code on any claim rated difficulty ≥ 0.5*), two of four
drafts repeated the kind of error the lesson was supposed to catch.
The lesson for the next wave is sharper: **the syn step should
re-verify any "exact contract" / "matches X's behavior" claim against
the source, not just cite it.**

**Net characterization of draft1 (the wave as a whole):** the
architecture is settled and correct. The migration is bounded
(ds4f's ~64 unique sites is the most defensible count). The open
questions are two policy decisions (dedupe identity, projection spec)
and one verification (implicate cycles in live playbooks). The plan
is executable. The canonical draft1 (§4) is the assembly.

## 7. References

### Wave sources (this synthesis's inputs)

- [`draft1.glm52.md`](/home/rektide/src/compfuzor/.design/merge-star/draft1.glm52.md) — fixed pipeline, no back-compat, explicit signals
- [`draft1.ds4f.md`](/home/rektide/src/compfuzor/.design/merge-star/draft1.ds4f.md) — fixed-step pluggable pipeline, consistency-first
- [`draft1.gpt56t.md`](/home/rektide/src/compfuzor/.design/merge-star/draft1.gpt56t.md) — explicit layers, explicit presets, no compatibility surface
- [`draft1.m3.md`](/home/rektide/src/compfuzor/.design/merge-star/draft1.m3.md) — explicit pipeline, no shims

### Prior wave (carried forward)

- [`draft0.md`](/home/rektide/src/compfuzor/.design/merge-star/draft0.md) — the design under review
- [`review0.glm52.md`](/home/rektide/src/compfuzor/.design/merge-star/review0.glm52.md) /
  [`review0.ds4f.md`](/home/rektide/src/compfuzor/.design/merge-star/review0.ds4f.md) /
  [`review0.gpt56t.md`](/home/rektide/src/compfuzor/.design/merge-star/review0.gpt56t.md) — the review wave
- [`review0-syn0.glm52.md`](/home/rektide/src/compfuzor/.design/merge-star/review0-syn0.glm52.md) — the prior synthesis (D1–D5)

### Live code referenced by every draft

- [`merge.py`](/library/filter_plugins/merge.py) — `_merge_keyed:259`, `_concat_strings_preserving_tags:296`, `_collect_payloads:425`, `_positional_strategy:411`, `_SKIP_CHECKS:113`, `_dedupe_preserve:37`, `_deep_merge_dicts:725`
- [`merge_strategy.py`](/library/filter_plugins/merge_strategy.py) — duplicate `_merge_keyed:16` (untagged concat `:46`), `STRATEGY_PROFILES:70`, `bins_generated:82`, `replace:301`
- [`merge_subsys.py`](/library/lookup_plugins/merge_subsys.py) — `ARTIFACT_DEFAULTS:111` (the live third registry)
- [`mergeKeyed.py`](/library/filter_plugins/mergeKeyed.py) — third `merge_keyed` surface
- [`helpers.py`](/library/filter_plugins/helpers.py) — `resolve_helpers:40`, nuclear guard `:68`, bypass-as-layer `:78`
- [`arrayitize.py`](/library/filter_plugins/arrayitize.py) — `_normalize_single:15`, **`True/False→[]:16`** (the bool-drop ds4f+gpt56t caught)
- [`listify.py`](/library/filter_plugins/listify.py) — **dict→list-of-{key,value}:10-11** (the shape-transform ds4f caught), redundant `concat:17`
- [`bin_composers.py`](/library/filter_plugins/bin_composers.py) — Python-internal `_arrayitize:23`
- [`dictify.py`](/library/filter_plugins/dictify.py)
- [`files/_bin`](/files/_bin) — where `helper_layers` is built (§9 of every draft)
