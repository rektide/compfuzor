---
type: Synthesis
title: "draft1-syn0 — merge-star: four draft1s collapse to one converged core + four open forks"
description: Synthesis of the draft1 wave (ds4f, glm52, gpt56t, m3). The four drafts agree on ~90% of the design — fixed shape, three-class skip, folds-over combines, two typed registries, dictify_union, tag-preserving keyed_fold, Stage 0 first, helpers preset with caller-side nuclear. They genuinely fork on four points: the public API surface (explicit layers vs incremental strategy=), as_list's False semantics (strict vs arrayitize-exact), mergeKeyed's fate (keep name vs delete), and the subsystem_* profiles (remove vs re-derive). I verify the wave's migration counts against the live tree, find a real internal contradiction (glm52/m3 adopt explicit-signals but keep arrayitize's truthiness in as_list), and surface one live render-diff risk nobody flagged (vars_nvim passes narrow bins_generated concat_fields). Net: the wave went from draft0's caution to decisive consensus; what's left is four calls, three of them cheap.
resource: /home/rektide/src/compfuzor/.design/merge-star/draft1-syn0.ds4f.md
tags: [compfuzor, merge, pipeline, architecture, synthesis]
status: draft
generated: { by: llm:ds4f, at: 2026-08-03T00:00:00Z }
verified: { by: llm:ds4f, at: 2026-08-03T00:00:00Z }
sources:
  - id: draft1-ds4f
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft1.ds4f.md
    title: draft1.ds4f — consistency-first revision
  - id: draft1-glm52
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft1.glm52.md
    title: draft1.glm52 — no back-compat, explicit signals
  - id: draft1-gpt56t
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft1.gpt56t.md
    title: draft1.gpt56t — explicit layers, explicit presets, no compatibility surface
  - id: draft1-m3
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft1.m3.md
    title: draft1.m3 — explicit pipeline, no shims
  - id: draft0
    resource: /home/rektide/src/compfuzor/.design/merge-star/draft0.md
    title: draft0 — the design all four revise
  - id: syn0
    resource: /home/rektide/src/compfuzor/.design/merge-star/review0-syn0.glm52.md
    title: review0-syn0 — the review-wave synthesis all four integrate
  - id: merge-tree
    resource: /home/rektide/src/compfuzor/
    title: live tree greps for migration counts (verified 2026-08-03)
---

# draft1-syn0 — four draft1s collapse to one converged core + four open forks

## 0. The situation in one paragraph

Four models ([ds4f](/.design/merge-star/draft1.ds4f.md), [glm52](/.design/merge-star/draft1.glm52.md), [gpt56t](/.design/merge-star/draft1.gpt56t.md), [m3](/.design/merge-star/draft1.m3.md)) independently revised [draft0](/.design/merge-star/draft0.md), each integrating the three review0 waves and [syn0](/.design/merge-star/review0-syn0.glm52.md) plus the user's directive: **explicitness and consistency over backwards compatibility**. The result is not four designs — it's **one design with a ~90% consensus core and four genuine forks**. The consensus is so thick that a reader of any single draft1 gets almost all of the design. This synthesis states the consensus as the target document, isolates the four forks, and settles as many as the evidence allows. I also re-ran the migration-count greps against the live tree, because the drafts disagree with each other *and with reality* on the numbers, and those numbers are what the "do the migration" principle is priced against.

## 1. The converged core — don't relitigate

All four drafts agree on the following. This is the design. Anything below is settled.

### 1.1 The pipeline (all four, same shape)

```
collect → combine (exactly one) → refine (ordered list) → extract (get_path)
```

- **`collect`** is mechanism-fixed: spread sources one level into payloads, apply the **layer-skip** policy. `skip` lives here, not as its own stage.
- **`combine`** is pluggable, exactly one. **Grouped by folds-over** (list-scalar / list-record / dict / any), *not* list-vs-dict — the draft0 split was decorative. The vocabulary: `concat`, `keyed_fold`, `union`, `dictify_union`, `replace` (any-type).
- **`refine`** is an ordered list, empty by default: `dedupe`, `dedupe_by` (first-key position, last value), `canonicalize` (registry reorder), `implicate` (deps-graph fixpoint; cycle→error, unknown→ignore, non-mutating).
- **`extract`** is `get_path`. No change.
- **`dictify_union` is a named combine** (D3, ds4f+gpt56t's lean won): `collect` stays mechanism-only, no `map=` slot. `tool_versions_overlay = (dictify_union, [])`.
- **One `keyed_fold`, the tag-preserving one** (D5): `merge.py`'s survives, `merge_strategy.py`'s tag-dropping duplicate is deleted, with an AnsibleTagHelper-propagation test.

### 1.2 Skip: three operation classes (all four)

| class | example | home |
|---|---|---|
| **absence** | `base_helpers` undefined / `None` | skip, default-on (`none`, `undefined`) |
| **suppress** | `base_helpers: False` | skip, opt-in `false` = `v is False` (strict identity, never falsy) |
| **nuclear** | `helpers: False`, `no_header: true` | **caller-side guard before the pipeline** — the pipeline never models poison |

The hardest syn0 item — gpt56t's layer/element skip conflation (difficulty 0.5) — was **de-scoped by running the code**: `False`-as-layer and `[False]`-as-layer are cleanly distinguishable under the one-deep spread. What was rated the scariest finding became a documentation question. Every draft1 lands this identically.

### 1.3 Two typed registries (all four)

- **`VALUE_PRESETS`** — `{name: (combine, refines[], args, folds-over)}`. Strategy names live here and only here.
- **`FIELD_PROFILES`** — `{name: {field: value_preset_name}}`. **References, never re-defines** a combine/refine.
- **`bins_generated` is a shape collision, not a value disagreement**: the value-preset is `merge_keyed` with `concat_fields=[early, generated, run_all]` (the superset); the field-profile `{BINS: bins_generated}` references it. The two old definitions were a value-preset and a field-profile wearing one name.
- **`ARTIFACT_DEFAULTS` (`merge_subsys.py:111`) is the live third registry** — the one playbooks actually dispatch through. It becomes the canonical field-profile projection. `subsystem_contrib` / `subsystem_artifacts` (zero internal callers) are re-derived from it, or removed.
- **One validator** after Stage G; exit criteria are *invariants* ("only the preset table interprets strategy names"), not "no switch."

### 1.4 Helpers as the example (all four)

`resolve_helpers` becomes a preset call over the generic pipeline and knows **no field names**:

```
preset "helpers" = (concat, [dedupe, implicate(HELPER_DEPS), canonicalize(HELPERS)])
skip = "false,none,undefined"
```

- `bypass → [report, guard]` is a **layer contributed by `files/_bin` before resolution** (it must precede rendering of the bypass block).
- Nuclear opt-out (`helpers: False`, and the `no_header: true` alias) is caller-side, in `_bin`.

### 1.5 Staging (three of four: `0 → D → E → F → G → H`)

**Stage 0** (contract + characterization tests, gpt56t's matrix) gates all extraction. Then D (register vocabulary + one keyed_fold + helpers recast), E (`merge_with_strategy` as field-profile dispatch + `bins_generated` superset), F (normalizer + positional-strategy removal), G (registry unification), H (liveness + explicit exclusions). **`subsys_publish` / `_deep_merge_dicts` are explicitly excluded** — publish/mutate, not merge.

## 2. The four genuine forks

Everything below is where the drafts split, and where the synthesis has to take a position.

### Fork 1 — the public API surface: gpt56t's redesign vs the others' incremental `strategy=`

- **gpt56t** is the radical: `merge_list(layers, *, preset=…, skip_layers=…, get=None)` — `layers` is *one sequence*, **no variadic `*extra`, no `single=`, no `strategy=`/`op` envelope**, `merge_with_strategy` renamed `merge_fields` (its `aggregate`/`into`/`payload_path`/`single` kwargs removed), `mergeKeyed` deleted.
- **ds4f / glm52 / m3** keep the entry-point signatures and only migrate the *positional string* to a `strategy=` keyword. ds4f explicitly keeps `into`/`single`/`aggregate`/`payload_path` as a "record-level collect analog in the adapter."

**The stakes.** The variadic `merge_list(values, *extra, single=…)` *is* the same class of ambiguity P2 exists to kill: is a positional string a payload or a strategy? gpt56t removes the whole class; the others remove only the strategy-string member. Under the user's own directive, gpt56t is the faithful continuation. But it triples the cutover shape-change (every call site's *argument structure*, not just a keyword) for a surface with ~15 positional sites.

**Synthesis position: adopt gpt56t's explicit-layers contract as the Stage 0 *target*, land it in the same cutover as `strategy=`.** The Stage 0 test suite should pin the *new* contract (removed spellings fail loudly), which is exactly gpt56t's Stage 0. If the human judges the blast radius too large for one pass, the fallback is ds4f/m3's incremental `strategy=` migration with `single=`/variadic kept — defensible, but it preserves an ambiguity P2 names. This is the one fork I genuinely cannot decide for you: it is a cost call, not a design call. My recommendation is gpt56t's target.

### Fork 2 — `as_list` False semantics: strict vs arrayitize-exact *(the internal contradiction)*

- **ds4f + gpt56t**: `as_list(False) → [False]`. **`False` is data in a normalizer.** `as_list` never reproduces `arrayitize`'s silent `True/False → []`. Sites that relied on the dropping get an explicit caller-side policy.
- **glm52 + m3**: `as_list` ships with **`arrayitize`'s exact contract** (including `False`/`True → []`), per syn0's D4.

**This is a real contradiction *inside the wave*, and it's mine to call out:** glm52 and m3 both adopt the explicit-signals principle (P3 — "we never collapse `False` into falsy") yet hand the same `False` to the truthiness-dropping normalizer they're shipping as the replacement for `arrayitize`. Those two positions are incompatible. If `False` is an explicit layer signal, `as_list` must keep `False` as data, or `X | arrayitize` → `X | as_list` silently deletes legitimate `False` values at ~50 sites. Syn0's D4 predates the P3 decision and was carried forward unexamined.

**Synthesis position: strict (ds4f + gpt56t).** The explicit-signals principle, which all four adopted, forces it. Migration remains classification work (gpt56t): every arrayitize site gets read for its *intended* False semantics; those that meant "False means no value" get an explicit filter before `as_list`. Stage 0's per-site characterization guards the rest. This also *shrinks* Fork 1's risk, since strict `as_list` never silently drops.

### Fork 3 — `mergeKeyed` fate: keep the name (ds4f, m3) vs delete (glm52, gpt56t)

- **m3** has the sharpest framing: P2 removes *machinery* (shims, positional tricks, synonyms, aliases), not *named APIs*. `mergeKeyed` is a named public filter with **2 live callers**; rewritten as a one-line field-profile dispatch it is *the new design's surface*, not back-compat.
- **glm52 + gpt56t** take the stricter P2 read: delete it, migrate `vars_mcp.tasks:48` and `vars_nvim.tasks:4` to `merge_list(…, strategy='merge_keyed')`.

**Synthesis position: keep the name, as a one-line preset dispatch (m3).** Deleting a named public filter that maps one-to-one onto a value-preset removes a *name*, not *machinery* — the strict read overreaches. But see §3: keeping it makes the `bins_generated` concat_fields resolution a live render risk.

### Fork 4 — `subsystem_contrib` / `subsystem_artifacts`: remove (gpt56t) vs re-derive (ds4f, glm52, m3)

- **gpt56t** deletes both: no internal caller justifies a second global profile registry; docs migrate to explicit profiles.
- **ds4f / glm52 / m3** re-derive them from `ARTIFACT_DEFAULTS`, preserving the documented public API (README/arch.md).
- **m3** adds the killer detail: the re-derivation is **not exact** — `ARTIFACT_DEFAULTS` has fields (`ETC_DIRS`) not present in `subsystem_contrib`, and the field sets only overlap. A re-derivation therefore needs a real typed projection spec, not a copy, plus a sync test.

**Synthesis position: remove (gpt56t), and flip syn0's Q1 lean.** Syn0 leaned re-derive because it was "cheap and preserves the surface." But m3 showed the derivation isn't even exact, and ds4f showed zero internal callers — a derived registry that nothing calls and that can't be derived exactly is drift with no value. The only thing that keeps re-derive alive is an external consumer, which is exactly the check glm52 asked for but nobody ran: **is any consumer downstream of compfuzor using `subsystem_contrib`/`subsystem_artifacts`?** Grep the tree, ask. If no, remove; if yes, re-derive with m3's projection spec. This is now an evidence question, not a taste question.

## 3. Verified corrections to the wave's numbers (my code-run findings)

The drafts disagree with each other *and with reality* on migration counts. I grepped the live tree. The table shows who was right:

| surface | ds4f | glm52 | gpt56t | m3 | **verified** |
|---|---|---|---|---|---|
| positional `merge_list('…')` | 14 | ~14 | — | ~45 | **15** (`tasks/compfuzor/*.tasks`) |
| positional `merge_dict('…')` | 0 | — | — | — | **0** |
| `arrayitize` pipe-form | 45 | ~37–45 | — | ~45 | **50** (pb/yaml/tasks globs) + **2** python (`bin_composers._arrayitize`) |
| `listify` sites | 1 (`concat` only) | ~8 | — | ~30 | **~4 mentions / ~3 live** (`k3s.srv.pb`, `vars/common.yaml`, `links.tasks`); `concat` = **1** live |
| `no_header` | 3 | — | — | — | **3** (confirmed: `pw-surround.etc.pb:38,46`, `vars_systemd_unit.tasks:208`) |
| `dict_overlay` | 1 | — | — | — | **1** (`vars/template-strategy-vars.yaml:35`) |
| `mergeKeyed` live callers | — | 2 | — | — | **2** (`vars_mcp.tasks:48`, `vars_nvim.tasks:4`) |

**What this means for the plan:**

1. **The migration is ~75 sites, not ~120.** m3's total (and its ~30 listify figure) is overstated; the real bulk is arrayitize's 50 + positional 15 + the small aliases. glm52's ~60–70 was closest. This shrinks Stage F — the work is more bounded than the scariest draft1 said.
2. **Syn0's "bless the shim" was priced on a phantom.** Item 22's "~45 callers" for `_positional_strategy` conflated the arrayitize count. The real number is 15. The user's P2 call ("14 sites is bounded, mechanical work") is confirmed at 15 — even cheaper than the synthesis that opposed it.
3. **`vars_nvim.tasks:4` is a live render-diff risk nobody flagged.** It calls `mergeKeyed(bins, key='name', concat_fields=['generated'])` — the **narrow** form. Resolving `bins_generated` to the superset `[early, generated, run_all]` changes this caller's output wherever a record carries `early`/`run_all` fields. glm52's open question (a) — "does any rendered bin rely on the narrow concat_fields?" — is answered: **yes, one does.** The superset is probably still right (most BINS records only carry `generated`), but this needs an actual render-diff check before Stage E, not an assumption. This is also the strongest *empirical* confirmation of the shape-collision thesis: the two live usages genuinely disagree.
4. **`strategy=` keyword already exists at 6 sites** — the kwarg form is not foreign to the tree, which cheapens Fork 1's incremental option.

## 4. The synthesized target document (best-merge of the four)

This is my vision of the best draft1 — the consensus core plus the four forks resolved as above. It is *not* a new draft; it's the merge. A draft2 that wants to be the tip can be written directly from this section.

### 4.1 API target (Fork 1 resolution, staged)

```python
merge_list(layers, *, preset="append", skip_layers=("none", "undefined"), get=None)
merge_dict(layers, *, preset="overlay", skip_layers=("none", "undefined"), get=None)
merge_fields(records, *, profile, get=None)     # was merge_with_strategy
as_list(value)                                   # strict: False is data (Fork 2)
```

- `layers` is one sequence; no variadic, no `single=`. Callers wrap: `[a, b] | merge_list(preset=…)`.
- Field profiles use gpt56t's non-overlapping leaf/nested syntax: `{'preset': …}` (leaf) vs `{'fields': …}` (nested). The `{op:…}` envelope is gone.
- **Cutover staging:** one pass over the ~15 positional sites to `preset=` *and* the explicit-layers shape (gpt56t's Stage 2), rather than two migrations. If the human defers Fork 1, fall back to ds4f/m3's incremental `strategy=` — but then the `single=`/variadic ambiguity is consciously retained, documented as such.

### 4.2 Registries (consensus + gpt56t's `order`)

- `VALUE_PRESETS` (consensus table, all four).
- `FIELD_PROFILES`: `{bins_generated: {BINS: bins_generated}, subsystem_contrib: …, subsystem_artifacts: …}` — the `subsystem_*` two removed per Fork 4, pending the external-consumer grep.
- `ARTIFACT_DEFAULTS` **stays local to the lookup but only references central presets**, carrying gpt56t's `order` field (`current-first` / `incoming-first`) as lookup-owned policy. This dissolves the "promote vs local" wording split cleanly: semantics centralize in `VALUE_PRESETS`; policy (which preset per artifact, and layer order) stays with the consumer that owns it.
- **`bins_generated` superset resolution is provisional until a render-diff on `vars_nvim`** (§3.3).

### 4.3 Helpers (consensus, all four)

As §1.4. The only addition: the `_bin`-contributed bypass layer and the nuclear guard are the *first* thing `_bin` computes, before any rendering — gpt56t's jinja sketch is the clearest statement of this.

### 4.4 Refines

- **`dedupe` identity: fix to equality in Stage 0** (glm52's position; I'm reversing my draft1 "document the wart" lean). Reason: Stage 0 is precisely where a deliberate behavior change is cheapest to assert, the affected set is pathological (`[1,"1"]`, str-colliding dicts), and a wart that changes behavior is a shim of its own kind under P2. gpt56t's *restraint* principle is still honored: it's a named Stage 0 decision with its own test, not a silent change bundled into extraction.
- `implicate`: cycle→error stands (consensus), but Stage 0 first characterizes whether any live graph is cyclic — ds4f's flagged risk, cheaply retired.
- `empty` skip predicate: keep only if Stage 0 finds a caller (ds4f's position; consensus is split on its existence).

### 4.5 Staging (consensus order, with two m3 corrections adopted)

- **Split Stage 0 in two halves** (m3's chicken-and-egg catch): (a) current-behavior characterization, (b) post-D target characterization for the helpers preset (needs the bypass-layer hook).
- Keep `0 → D → E → F → G → H`. Stage F shrinks to the verified ~75 sites; Stage E includes the `vars_nvim` render-diff gate before the `bins_generated` superset lands.
- Stage H unchanged: liveness-check `subsys_publish`/`merge_*_subsys`; `_deep_merge_dicts` excluded.

## 5. Cross-comparison of the four drafts

| draft | strength | most notable contribution | relative weakness | characterization |
|---|---|---|---|---|
| **gpt56t** | the only one to redesign the *entry surface* end-to-end; the vocabulary/ownership table (term → definition → owns it) is the clearest statement of *who owns what* in the whole wave | explicit-layers API + `preset=` keyword-only + non-overlapping `{'preset'}`/`{'fields'}` profile syntax; `ARTIFACT_DEFAULTS`-stays-local-with-`order`; the restraint principle | the most breaking of the four — its blast radius (every call site's shape) is the thing the other three spent their conservatism avoiding; doesn't verify against the tree, so `single=`/variadic removal is argued, not sized | the API architect: "the ambiguity is the API's shape, not a missing keyword" |
| **glm52** | the integration memoir — the most honest about provenance ("draft1 is mostly theirs") and about the skip finding's role in deflating the whole plan; cleanest statement of the P2→migrate table | the only **fix-to-equality** position on `dedupe`; the open-question list (downstream consumer check, narrow-concat_fields check) that §3 partially answers | keeps `as_list`'s arrayitize-exact contract (Fork 2 contradiction); the open-questions are left open rather than resolved | the editor: "the design is a synthesis and the synthesis is mostly citation" |
| **ds4f** (me) | ran the code — the verified `False`/`[False]` distinction that de-scoped syn0's hardest item; three-class skip named; explicit non-goals | the `strategy=` site-count (14/15) that priced P2 correctly; the nuclear-gap catch (draft0's §6 preset silently downgraded nuclear); the `implicate` cycle-risk flag | kept the entry signatures (Fork 1 conservatism); "document the dedupe wart" leaned the wrong way and I reverse it here | the verifier: "run the code before believing a claim rated difficulty ≥ 0.5" |
| **m3** | the most honest self-critique in the wave — 10 numbered confessions, most of which *are* real gaps; the only one to draw the machinery-vs-named-API line under P2 | **`ETC_DIRS`-not-in-`subsystem_contrib`** (the re-derivation is not exact); Stage 0 chicken-and-egg with Stage D; the `compat.py` fallback honesty | overstated counts (~30 listify, ~120 total); keeps arrayitize-exact `as_list` (Fork 2); keeps `noop` refine nobody asked for | the auditor: "here is exactly where my own argument leaks" |

**Where they agree** is the design; **where they disagree** is exactly four points, and the four are cheap: one is a cost call (Fork 1, human), one is settled by an internal contradiction (Fork 2 → strict, the evidence is their own principle), one by a name-vs-machinery read (Fork 3 → keep), one by a grep (Fork 4 → remove, pending the external-consumer check). No two drafts occupy the same "corner" on all four forks — they tile the space the way the reviews did, which is why the union looks bigger than it is.

## 6. Net characterization + what needs a human

**Net.** The wave succeeded. Draft0 had the right thesis and a leaky inventory; the review wave (syn0) turned 25 findings into 5 decisions; the four draft1s turned those 5 into a ~90%-shared design and, under the user's P2 directive, went from "keep shims" to "migrate and delete." The residual risk is no longer architectural — it's the ~75-site cutover, de-risked by Stage 0. The single most load-bearing verified fact of the wave is the `False`/`[False]` distinction, because it converted the hardest syn0 item into a doc question and let every draft1 commit to strict signals with confidence.

**Needs the human:**

1. **Fork 1** (Fork 1 above): gpt56t's full explicit-layers target, or the incremental `strategy=` fallback. Cost call — the only real one left. (My rec: full target.)
2. **Fork 4's grep**: is any consumer *outside the repo* using `subsystem_contrib` / `subsystem_artifacts`? Remove or re-derive hangs on this.
3. **A render-diff on `vars_nvim.tasks`** before the `bins_generated` superset lands (narrow→wide concat_fields). Cheap, and it either confirms the superset or finds the first case where "superset is low-risk" is wrong.

**Everything else in this synthesis is the four drafts converging; take it to the tip.**

## References

- [`draft1.ds4f.md`](/.design/merge-star/draft1.ds4f.md) / [`draft1.glm52.md`](/.design/merge-star/draft1.glm52.md) / [`draft1.gpt56t.md`](/.design/merge-star/draft1.gpt56t.md) / [`draft1.m3.md`](/.design/merge-star/draft1.m3.md) — the wave this synthesizes
- [`draft0.md`](/.design/merge-star/draft0.md) — the design all four revise
- [`review0-syn0.glm52.md`](/.design/merge-star/review0-syn0.glm52.md) — the review-wave synthesis all four integrate
- `tasks/compfuzor/*.tasks` — the 15 positional `merge_list('…')` sites and 2 `mergeKeyed` callers (`vars_nvim.tasks:4`, `vars_mcp.tasks:48`)
- `k3s.srv.pb:186`, `vars/common.yaml:988`, `tasks/compfuzor/links.tasks:27` — the live `listify` sites
- `pw-surround.etc.pb:38,46`, `vars_systemd_unit.tasks:208` — `no_header`
- `vars/template-strategy-vars.yaml:35` — `dict_overlay`
