---
type: History
title: "Merge and bin-helper closure history"
description: "Authoritative chronology and completion record for the disarm, bin-helper, merge-star, cfmerge, and null/default cleanup work."
resource: /.design/merge-star/history.md
tags: [compfuzor, merge, cfmerge, bins, helpers, migration]
status: stable
generated: { by: "agent:opencode:gpt-5.6-sol", at: 2026-08-07T00:00:00Z }
verified: { by: "agent:opencode:gpt-5.6-sol", at: 2026-08-07T00:00:00Z }
stale_after: 2026-11-07
sources:
  - id: bin-helpers-design
    resource: /.design/bin-helpers/init.glm52.md
    title: "Bin helpers: composable, opt-in template sections"
    author: "llm:glm52"
    last_modified: 2026-08-02
  - id: merge-star-draft3
    resource: /.design/merge-star/draft3.gpt56t.md
    title: "Merge-star fixed pipeline design"
    author: "llm:gpt56t"
    last_modified: 2026-08-03
  - id: merge-star-stage0
    resource: /.design/merge-star/stage0.gpt56t.md
    title: "Merge-star target contracts and migration inventory"
    author: "llm:gpt56t"
    last_modified: 2026-08-03
  - id: cfmerge
    resource: /library/filter_plugins/cfmerge.py
    title: "Active fixed merge pipeline"
    last_modified: 2026-08-03
  - id: template-data
    resource: /library/filter_plugins/template_data.py
    title: "Non-rendering Ansible template-data boundary"
    last_modified: 2026-08-03
  - id: null-defaults-pass
    resource: /.design/null-defaults-pass/init.glm52.md
    title: "Null, empty, and default cleanup inventory"
    author: "llm:glm-5.2"
    last_modified: 2026-08-04
  - id: plugin-catalog
    resource: /library/README.md
    title: "Current Ansible plugin catalog"
    last_modified: 2026-08-07
---

# Merge and bin-helper closure history

## Purpose

This is the current status record for the merge/helper work. The earlier files
under [`/.design/merge-star/`](/.design/merge-star/) remain useful design and
migration evidence, but they are not a current API reference or completion
ledger. Use [`/library/README.md`](/library/README.md) and the active modules for
current behavior.

## Chronology

| Date | Change | Result |
|---|---|---|
| 2026-07-27 | Disarm introduced `_cf_action_*`, guard, and reporting primitives. | Generated bins gained a structured action/skip lifecycle. |
| 2026-07-28 | `bypass:` became a BINS record field. | Bin templates could request scalar or unit-qualified bypass guards. |
| 2026-08-02 | The bin-helper design decomposed the monolithic header into `env`, `setopts`, `loud`, `report`, and `guard`; implementation and helper merge delegation followed. | Helper selection became layered and canonical while `files/_bin` retained field policy. |
| 2026-08-02 to 2026-08-03 | The merge-star design/review/synthesis wave converged on `collect -> normalize -> combine -> refine -> extract`, explicit presets, tag-preserving keyed folds, and a non-rendering lazy-data boundary. | The migration contract and risky callers were identified before activation. |
| 2026-08-03 | The implementation became `cfmerge.py`; public filter registration cut over, callers migrated, lazy template data was preserved, and `normalize`, `join2`, `combine_iff`, and rendering support were completed. | `cfmerge` became the public merge owner, while alternate legacy filter modules remained discoverable for soak. |
| 2026-08-04 to 2026-08-07 | The null/default cleanup used the undefined-tolerant filters to remove redundant Jinja defaults and clarify flag handling. | The inventory served its migration purpose; its original counts are no longer current. |
| 2026-08-07 | The last `listify | concat` caller moved to variadic `merge_list`; alternate legacy plugins/tests were disabled for soak; `_bin` bypass closing was fixed; real-Ansible helper and lazy keyed-BINS acceptances were added; the root README and full-suite guidance were refreshed. | The agreed merge/helper implementation closure is complete. |
| 2026-08-07 | Automatic BINS disarm metadata was added at the active `merge_subsys` boundary, mergeable provenance/scope fields joined `bins_generated`, and `_bin` gained one canonical resolver for automatic plus explicit policy. Manual aggregators and systemd phase aliases were reconciled. | Standard subsystem actions now receive broad and nested guards without routine scope authoring; reports identify the actual script and contributing subsystems. |

## Accepted API Drift

The design snapshots often show one explicit collection of layers. The
accepted public Jinja API is instead variadic layers with a keyword-only
`preset=`:

```jinja2
{{ X | merge_list(Y, Z, preset='append') }}
{{ X | merge_dict(Y, preset='overlay') }}
{{ X | merge_list(Y, preset={
  'name': 'merge_keyed',
  'key': 'name',
  'concat_fields': ['generated'],
}) }}
```

The filter input is the first layer, each positional argument is another layer,
and layer order is preserved. A positional strategy name and the old
`strategy=`, `single=`, or listify/concat compatibility forms are not accepted.
This drift was accepted during cutover because it makes pipeline use natural in
Jinja while retaining explicit, keyword-only behavior selection.

## Document Freshness

| Document set | Date | Current use | Stale claims |
|---|---|---|---|
| [`bin-helpers/init.glm52.md`](/.design/bin-helpers/init.glm52.md) | 2026-08-02 | Rationale and helper decomposition. | It describes the pre-implementation `_bin.header` state and should not be used as a path or current-state reference. |
| `merge-star` draft/review/synthesis wave | 2026-08-02 to 2026-08-03 | Decision history and rejected alternatives. | Signatures and legacy source paths predate the accepted variadic API and disabled soak filenames. |
| [`stage0.gpt56t.md`](/.design/merge-star/stage0.gpt56t.md) | 2026-08-03 | Historical migration ledger and risk inventory. | Its "not started" gates, `merge_pipeline.py` name, active-legacy-module claims, and pending NVIM/helper acceptance status are superseded. |
| [`null-defaults-pass/init.glm52.md`](/.design/null-defaults-pass/init.glm52.md) | 2026-08-04 | Pattern inventory and rationale. | Counts and remaining-site estimates predate the cleanup commits through 2026-08-07. |

These documents should remain immutable historical inputs unless a separate
documentation cleanup explicitly promotes or supersedes them.

## Current State

- [`cfmerge.py`](/library/filter_plugins/cfmerge.py) exclusively owns active
  list, mapping, and field merge behavior.
- [`template_data.py`](/library/filter_plugins/template_data.py) is the shared
  non-rendering boundary used by merge and lookup code.
- Same-name keyed BINS collisions preserve tagged generated templates until
  final Ansible rendering and concatenate body plus disarm metadata in layer
  order. Public `bypass` remains ordinary later-wins data.
- NVIM deliberately uses a configured narrow keyed merge: only `generated`
  concatenates; later `early` and `run_all` values replace earlier values.
- [`merge_subsys.py`](/library/lookup_plugins/merge_subsys.py) annotates active
  incoming BINS with origin and broad scope before cfmerge. Scope precedence is
  explicit domain, record domain, then subsystem ID.
- [`bin_disarm.py`](/library/filter_plugins/bin_disarm.py) owns annotation,
  action canonicalization, stable metadata deduplication, effective guard
  entries, derived verbs, and report labels.
- [`files/_bin`](/files/_bin) invokes that resolver once. Effective entries
  control helper inclusion, guard opening, and action closing; `bypass: false`
  suppresses outer policy and `helpers: false` remains nuclear.
- Generated compositors remain unguarded parents and do not aggregate child
  metadata. `run_all`, `base_helpers`, and the env helper are unchanged.
- Systemd's canonical internal phase variables are
  `COMPFUZOR_SYSTEMD_{LINK,ENABLE,START}_BYPASS`; old
  `SYSTEMD_BYPASS_*` spellings remain temporary soak aliases.
- Deprecated implementations are retained for soak as
  `library/filter_plugins/*.py.deprecated`. Ansible scans `*.py`, so the
  superficially attractive `merge.deprecated.py` form would still be loaded.
- Obsolete tests are retained as `tests/filter_plugins/*.test.py.deprecated`,
  outside the normal `*.test.py` discovery loop.
- The current plugin paths and statuses are cataloged in
  [`library/README.md`](/library/README.md).

## Verification Evidence

Evidence collected on 2026-08-07:

| Check | Evidence |
|---|---|
| Full documented suite | The root README command runs `tests/filter_plugins/*.test.py`, `tests/lookup_plugins/*.test.py`, and `tests/integration/*.test.py`; it completed successfully and did not select disabled obsolete tests. |
| Fixed pipeline | `python tests/filter_plugins/cfmerge.test.py` passed 109 assertions, including provenance concatenation, later-wins bypass, template-tag, and lazy-container cases. |
| Lookup helper import | `python tests/lookup_plugins/subsys.test.py` passed 37 assertions using `template_data` directly. |
| Automatic disarm unit/lookup | `bin_disarm.test.py` covered canonicalization, scope subtraction, extension, false, TYPE fallback, annotation, and errors; `merge_subsys.test.py` passed 22 assertions including domain precedence and lazy incoming BINS. |
| `_bin` integration | `tests/integration/bin_helpers.test.py` rendered and syntax-checked eight scripts through real Ansible, then executed safe automatic run/skip paths. It covered actual filenames, derived/authored verbs, labels, automatic broad/action guards, explicit global/unit extensions, TYPE fallback, `bypass: false`, `helpers: false`, and explicit macro labels. |
| Keyed BINS render/diff self-check | `tests/integration/cfmerge_bins.test.py` merged two same-name lazy generated templates before their variables existed, then verified final contribution order and completed `bash -n`. |
| NVIM negative assertion | The same real-Ansible test proved only `generated` concatenates while `early` and `run_all` are replaced by the later record. |
| Deprecated discovery | `ansible-doc -t filter arrayitize` reported that the filter was not found after the `.py.deprecated` rename. |
| Playbook syntax | `k3s.srv.pb`, `pstore.etc.pb`, `github-mcp.src.pb`, and `zim.opt.pb` passed `ansible-playbook --syntax-check`. |
| Systemd phases | Both systemd install scripts passed `bash -n`; canonical and temporary alias link bypasses were executed safely, and enable/start names were checked. |
| Root documentation | [`README.md`](/README.md) now presents `cfmerge`, active helper/composer concepts, disabled soak paths, and the full suite instead of legacy APIs/tests. |
| Patch hygiene | Focused and final `git diff --check` checks completed without errors. |

## Explicit Decisions

1. Keep current `run_all` and `base_helpers` ownership unchanged. Their explicit
   record fields preserve flexibility; do not infer one from the other.
2. Keep `DEFAULT_HELPERS` centralized in
   [`vars/common.yaml`](/vars/common.yaml). Do not move default ownership into
   `bin_composers` or individual playbooks.
3. Defer the env-helper behavior decision. This closure does not alter
   [`files/_helpers/env`](/files/_helpers/env).
4. Keep helper field policy in [`files/_bin`](/files/_bin) and generic helper
   merge mechanics in [`helpers.py`](/library/filter_plugins/helpers.py).
5. Keep compositor `subsystem` grouping independent from disarm provenance.
   `origin_subsystems` reports contributors and `bypass_scopes` supplies broad
   guards; neither is inferred from `subsystem`.
6. Keep public `bypass` later-wins. It extends automatic policy and is not a
   concat field.

## Remaining Work

- Let the disabled deprecated modules and tests soak. Delete the
  `.py.deprecated` and `.test.py.deprecated` files only in a separately reviewed
  cleanup after confidence in downstream/private consumers.
- Decide env-helper behavior separately, with its own contract and rendered-bin
  coverage.
- Clean up remaining stale legacy merge/helper claims in
  [`doc/bins.md`](/doc/bins.md). The active architecture and subsystem docs now
  describe cfmerge and automatic disarm behavior.
- Remove the systemd phase aliases only after generated artifacts and operators
  have completed their soak period.
- Mark newly discovered sourced/library `.sh` records `bypass: false` when a
  TYPE-fallback outer wrapper would be unsafe.
- Review this history by `stale_after`; update it sooner if the public cfmerge
  signature, helper ownership, or soak policy changes.

Run-all inference, `bin_composers` base-helper changes, and env-helper changes
are explicitly outside this closure.
