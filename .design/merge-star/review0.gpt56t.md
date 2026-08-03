---
type: Design Review
title: "merge-star review0: preserve semantic boundaries"
description: Review of draft0's fixed merge pipeline proposal, identifying the contracts needed before it can safely unify the existing merge family.
resource: /.design/merge-star/review0.gpt56t.md
tags: [compfuzor, merge, pipeline, architecture, review]
status: draft
generated: { by: llm:gpt56t, at: 2026-08-02T00:00:00Z }
sources:
  - id: merge-star-draft0
    resource: /.design/merge-star/draft0.md
    title: merge-star draft0
  - id: merge-implementation
    resource: /library/filter_plugins/merge.py
    title: Existing merge filters
  - id: merge-strategy-implementation
    resource: /library/filter_plugins/merge_strategy.py
    title: Existing per-field merge filter
  - id: helpers-implementation
    resource: /library/filter_plugins/helpers.py
    title: Existing helper resolver
---

# merge-star review0: preserve semantic boundaries

## Verdict

The `collect -> combine -> refine -> extract` shape is a useful internal model.
It makes the existing `append_unique` decomposition legible, provides a natural
home for one `merge_keyed` implementation, and should let `merge_with_strategy`
reuse value-level operations.

Do not approve the staged plan unchanged. It currently conflates three distinct
abstractions: normalization, value merge presets, and record-field profiles.
It also proposes an `arrayitize` migration that changes rendered playbook
behavior. Define these boundaries and test their contracts before Stage D/F.

## Blocking Corrections

### `arrayitize` is not `_as_list`

Draft0 says every `X | arrayitize` call is exactly `_as_list`, then proposes
`X | merge_list(single=True)`. The implementations disagree for meaningful
inputs:

| input | `arrayitize` | proposed `merge_list(single=True)` |
|---|---|---|
| `False` | `[]` | `[False]` with the default skip policy |
| `True` | `[]` | `[True]` |
| an arbitrary non-string `Sequence` | list of its members | one scalar unless it is list/tuple/set |

`arrayitize` treats booleans as absent for its single-input form
([`arrayitize.py:15-24`](/library/filter_plugins/arrayitize.py#L15-L24));
`merge_list` deliberately retains `False` by default for compatibility
([`merge.py:456-506`](/library/filter_plugins/merge.py#L456-L506)). The many
templated `arrayitize` callers therefore cannot be mechanically migrated.

Retain an explicit, public single-value normalizer whose contract matches
`arrayitize` until each caller is classified. Its implementation may share
low-level primitives with `collect`, but its boolean, Sequence, and undefined
semantics must be separately specified and tested. Retire `arrayitize` only
after callers either move to that normalizer or deliberately opt into merge
semantics.

### A skip policy cannot safely filter both layers and elements

The draft defines `false` as a layer suppression mechanism while `collect`
also removes skippable elements as it spreads a collection. Thus a layer value
of `[False]` is indistinguishable from a false layer when `skip=false`; it is
silently rewritten to `[]`. The current `_collect_payloads` already has this
property ([`merge.py:425-452`](/library/filter_plugins/merge.py#L425-L452)), so
the new architecture should not make it a foundational contract by accident.

Use separate concepts:

- `skip_layers`: omit a whole input layer such as `base_helpers: False`.
- Element preservation: combines and refines receive the contents of a
  surviving list unchanged unless a named refine removes them.

If element filtering is required by a real caller, give it an explicit named
refine or normalizer option. This preserves the distinction between "no layer"
and "a layer containing a false value."

### Value presets and field profiles are different registries

`append_unique`, `merge_keyed`, and `overlay` describe a merge of values.
`subsystem_contrib` and `bins_generated` in `merge_strategy.py` describe which
value merge to run for each field. Conversely, `bins_generated` in `merge.py`
is a value-level `BINS` preset. These cannot be literally "the same
definition," as Stage G currently requires.

Use one module if desired, but maintain typed namespaces:

```python
VALUE_PRESETS = {"append_unique": ... , "bins_generated": ...}
FIELD_PROFILES = {"subsystem_contrib": {"BINS": "append", ...}}
```

The `bins_generated` field profile should *reference* the shared value preset:

```python
FIELD_PROFILES["bins_generated"] = {"BINS": "bins_generated"}
```

This removes the divergence without forcing a list value and a record schema
into one registry shape. It also leaves space for nested field profiles, which
are structural recursion rather than a value-level combine/refine operation.

### Moving the bypass implication into `_bin` needs a concrete data flow

The rendered bypass block needs `report` and `guard`, but `_bin` first computes
`_helpers` and emits every helper include before it renders that block
([`files/_bin:2-8`](/files/_bin#L2-L8),
[`files/_bin:28-39`](/files/_bin#L28-L39)). `_bin` cannot contribute a helper
layer after calling `resolve_helpers`; the decision must occur before or during
the helper selection.

This is still compatible with a generic resolver, but the caller must provide
the layer explicitly, for example by building a template-local `helper_layers`
list which conditionally includes `["report", "guard"]`, then passing that to
a generic `resolve_helper_layers`. The generic merge primitive should not
inspect `bypass`; neither should the resolver. Document the exact call shape
and retain tests for the nuclear `helpers: False` / `no_header: true` opt-outs.

## Contracts The Draft Must Pin Down

### Refinement order and identity

`dedupe_by` is described only as "last wins." Existing behavior keeps the
*first key's position* while substituting its value with the last occurrence
([`merge.py:313-346`](/library/filter_plugins/merge.py#L313-L346)). A generic
refine must preserve that ordering or consciously change it with a migration
note and regression tests.

Likewise, `implicate` needs a defined cycle policy, unknown-node policy, and
deduplication behavior. Its output must remain a valid input to
`canonicalize`; today canonicalization drops unknown helper names. Specify
whether implications are transitively closed, whether dependency order affects
the result, and whether each refine receives an immutable copy or may mutate
its argument.

The present `_dedupe_preserve` identifies values by `str(value)`, not Python
equality ([`merge.py:37-46`](/library/filter_plugins/merge.py#L37-L46)). The
new refine's contract should state whether that historical behavior remains.
Changing it incidentally while extracting functions would be a behavior change.

### Combine identities and malformed payloads

Each combine needs an empty identity and malformed-input policy. The current
merge filters silently coerce non-list values for list operations and non-dict
values for dict overlay; `merge_with_strategy` additionally skips non-dict
records. State whether the pipeline preserves those leniencies or becomes
strict. In particular, `replace` currently means "latest non-None field
value," not merely "last collected payload."

`keyed_fold` also has observable order rules: keyed records follow first key
appearance, while non-keyed items are moved to their last occurrence. Preserve
the tag-preserving string concatenation in `merge.py`; the duplicate in
`merge_strategy.py` currently does not preserve Ansible tags, so choosing the
former is a real correctness improvement that merits an explicit test.

## Recommended Reframe Of The Stages

1. Define and test value-pipeline contracts: source-layer skip only, combine
   identities, each refine's ordering/mutation/error behavior, and tag
   preservation. Extract the shared `merge_keyed` and value presets without
   changing public filter behavior.
2. Make `merge_with_strategy` an adapter over value presets. Keep field-profile
   dispatch and nested-map recursion outside the value pipeline.
3. Refactor helper selection by giving `_bin` an explicit conditional helper
   layer before generic resolution. Do not make the merge framework know about
   `bypass`.
4. Audit normalization callers. Introduce a compatible named normalizer first;
   migrate only callers with equivalent desired semantics; then delete the
   duplicate normalizers.
5. Consolidate definitions in one module with separate value-preset and
   field-profile registries. Resolve the `bins_generated` field list through
   characterization tests before choosing the superset.

## Test Matrix Required Before Migration

- Normalizer: `None`, undefined, `True`, `False`, string, dict, tuple, set,
  and a non-list Sequence.
- Layer skip: `False` as a layer versus `[False]` as list content.
- `dedupe_by`: duplicate key value replacement and first-position retention.
- `keyed_fold`: list/string concat fields, non-keyed records, order, and
  Ansible-tag propagation.
- Refines: dependency transitivity, cycles, duplicate dependency, unknown
  value, and canonicalization ordering.
- Profiles: list-level and field-level `bins_generated` resolve through the
  same *value preset* and retain their current distinct input/output shapes.
- Helpers: bypass implication, `helpers: False`, `no_header: true`, narrowed
  defaults, and unknown helper filtering.

## Non-Blocking Notes

- Keep `skip` inside `collect` only if it is explicitly source-layer filtering;
  it does not need a visually separate pipeline box.
- `dedupe_by` belongs in `refine`: it operates on a fully concatenated list.
  `keyed_fold` belongs in `combine`: it resolves record conflicts during the
  fold and has no equivalent associative post-pass without reconstructing that
  fold.
- `tool_versions_overlay` is evidence for a per-payload normalization hook,
  but it should not expand the universal pipeline until another use case
  exists. A dedicated value preset that uses `dictify` is the smallest current
  design.
- "No strategy switch remains" is not a useful exit criterion. Registry lookup
  still dispatches; require one validated value-preset resolver and one shared
  implementation of each operation instead.
