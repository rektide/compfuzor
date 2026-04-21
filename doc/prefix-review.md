# Prefix Review: Gap Analysis

This document records what has been absorbed into the current architecture docs,
what remains uncovered, and what must be carried forward before older documents
are retired.

Documents under review:

- [`doc/pipeline-and-intent-prefix-memo.md`](pipeline-and-intent-prefix-memo.md) -- active implementation-facing memo (the "memo")
- [`doc/intent-prefix-system.md`](intent-prefix-system.md) -- original intent prefix design (the "system doc"; candidate for retirement)
- [`doc/prefix.codex.md`](prefix.codex.md) -- implementation-forward decomposition slices
- [`doc/prefix-transcript.md`](prefix-transcript.md) -- session transcript from which the codex and memo evolved

## 1. Transcript coverage in the memo

### Well represented

The memo captures the following from the transcript session:

- **Canonical terminology migration** (stage→phase, class→role, side-effect→effect) with explicit legacy-to-canonical table
- **Phase vocabulary and mapping** to `compfuzor.includes` regions
- **Domain lifecycle contract** (raw→norm→spec→syn→apply) with producer/output table
- **Domain activation contract** (`_REQUESTED` / `_BYPASSED` / `_VALID` / `_ACTIVE`)
- **`_syn_<domain>` handoff schema** with required keys
- **GET_URLS worked example** -- complete lifecycle table
- **Kernel/Zswap worked example** -- lifecycle table present
- **Authoring and mutation guidance** with authority boundaries per prefix
- **Merge policy recommendations** with user > existing > synthesized default
- **`fn_multi` minimum bar** preserved from the system doc
- **Success criteria** -- the four quick-answer questions

### Needs buffing

1. **Intent prefix enumeration** -- The full file-prefix and data-prefix table from [`intent-prefix-system.md`](intent-prefix-system.md) (vars_, probe_, fn_, gen_, repo_, fs_, bins, links, _*.tasks, raw_, norm_, spec_, drv_, out_, merge_, syn_, _tmp_, envelope shapes) is never enumerated. The memo says `kind` is a facet but does not list valid kinds or map file-intent vs data-intent patterns.

2. **Probe as first-class intent** -- `probe_` (`kind:probe`, `class:discovery`) had its own row and the transcript discussed `probe_systemd.tasks` as a target. The memo never mentions probes.

3. **Config and systemd decomposition seams** -- Listed as "key seams to retain" but not elaborated. The transcript explicitly specified `fn_config`/`gen_config` splits and `probe_systemd`/`gen_systemd` patterns. These deserve at least a sentence each or a cross-reference to [`prefix.codex.md`](prefix.codex.md).

4. **ETC_FILES as cross-cutting artifact** -- The transcript found 149 references across dozens of `.pb` files and task files. The memo's kernel example casually mentions `ETC_FILES` merge but does not address the real problem: many domains contribute to the same artifact, and merge policy needs to handle multi-domain aggregation (not just user > existing > syn per domain).

5. **Hierarchy and fanout system** -- The transcript explored `vars_hierarchy.tasks`, `fs_hierarchy.tasks`, and the `_multi.tasks` fanout pattern in depth. The memo does not address how the prefix system interacts with hierarchy vars or the multi-task dispatch mechanism. This is a significant gap because hierarchy is how compile-phase vars become fs-apply actions.

6. **Reusable decomposition template** -- The codex's four-slice pattern (add transform output → move synthesis → narrow execution → wire include order) is a repeatable template. The memo should reference this as the canonical migration method rather than leaving it implicit in the codex.

7. **Migration guardrails** -- The codex encoded specific guardrails (preserve BYPASS exactly, do not change host semantics first pass, fallback compatibility until second domain adopts, one merge per artifact). The memo says only "temporary migration shims are allowed." Should encode the guardrails normatively.

8. **BYPASS-to-activation mapping** -- The transcript shows dozens of `*_BYPASS` flags in the includes. The memo defines `<DOMAIN>_BYPASSED` in the activation contract but never shows how existing `GET_URLS_BYPASS`, `FS_BYPASS`, etc. map into the new `<DOMAIN>_BYPASSED` field.

9. **Data-intent envelope shapes** -- `_probe_<domain>`, `_fn_<domain>_out`, `_syn_<domain>` as transport envelopes with explicit `form:envelope` vs `form:prefix` distinction. The memo only has `_syn_<domain>`; the other envelopes and the form dimension are absent.

10. **Naming registry seed** -- Listed as TODO in the memo but the system doc already had a concrete naming table. Should be promoted from TODO to a stub section referencing that table.

## 2. Content to carry from the system doc before retirement

[`intent-prefix-system.md`](intent-prefix-system.md) contains material not yet present in the memo. The following must be absorbed before that document can be deleted.

### 2.1 The full prefix contract table

The complete enumeration of file-intent rows and data-intent rows with all facets per entity pattern (lines 44-67 of the system doc). The memo references `kind` as a facet but never lists the valid values. This table is the authoritative registry of what prefixes exist and what contracts they carry.

File-intent rows: `vars_`, `probe_`, `fn_`, `gen_`, `repo_`, `fs_`, `bins`/`bins_*`, `links`/`links_*`, `_*.tasks`.

Data-intent rows: `raw_`, `norm_`, `spec_`, `drv_`, `out_`, `merge_`, `syn_`, `_tmp_`.

Envelope shapes: `_probe_<domain>`, `_fn_<domain>_out`, `_syn_<domain>`.

### 2.2 Probe as a file-intent prefix

`probe_` with `kind:probe`, `class:discovery`, and the `_probe_<domain>` envelope form a whole intent category absent from the memo. This is not just a naming concern; it represents the discovery stage between foundation and transform.

### 2.3 The form dimension

`form:<prefix|envelope|internal>` distinguishes file prefixes from data envelopes from internal-only keys. The memo does not mention this facet at all. It is critical for understanding why `_tmp_` values should not escape their producing file and why envelope names are transport shapes rather than new kinds.

### 2.4 The "stage vs intent" principle

Lines 17-25 of the system doc: "Do not conflate them. Stage is when. Intent is what." The memo discusses phase and facets but never states this principle cleanly as a normative rule. It should be a prominently placed invariant.

### 2.5 Missing data-intent rows

`drv_` (derivation intermediates), `out_` (completed transform payloads), `merge_` (merge-ready payloads), `_tmp_` (short-lived scratch values). None appear in the memo. The lifecycle contract covers raw→norm→spec→syn→apply but skips the intermediate data shapes that complex transforms produce.

### 2.6 Envelope transport concept

`_probe_<domain>`, `_fn_<domain>_out`, `_syn_<domain>` as `form:envelope` with the note "data-intent prefixes are primary semantics; envelope naming is a transport shape for passing data between files." The memo only has `_syn_<domain>`. The envelope concept and its relationship to kind vs form should be preserved.

### 2.7 Config seam detail

The system doc specifies `fn_config.tasks` for parameterized config assembly and `gen_config.tasks` for default batteries-included behavior, with a `CONFIG_KEY` compatibility note. The memo lists config as a bullet under "seams to retain" but drops the specific file targets.

### 2.8 Systemd seam detail

The system doc specifies `probe_systemd.tasks` for discovery snapshot and `gen_systemd.tasks` for generated artifacts, noting this "removes ambiguity around old `vars_systemd` intent." The memo mentions systemd as a seam but omits the probe-first-class design.

### 2.9 The six-step authoring recipe

Validate contract → normalize input → build ordered spec table → derive outputs from spec → synthesize merge payload → apply in execution stages (lines 93-103). The memo has the lifecycle contract but not this prescriptive recipe for implementors.

### 2.10 The merge-block rule

"Prefer one explicit merge block over many tiny `set_fact` mutations." A concrete implementation rule that the memo's merge policy section does not capture.

### 2.11 Side-effect values per prefix

The system doc enumerates that `vars_`, `probe_`, `fn_`, `gen_` are all `side-effect:none`, while `repo_`, `fs_`, `bins`, `links` are `side-effect:host`, and `_*.tasks` is `side-effect:mixed`. The memo uses `effect` (renamed) but does not provide this enumeration.

## Summary

The memo is strong on lifecycle, activation, and worked examples. The gaps fall into two categories:

- **Structural gaps**: missing the full prefix table, form dimension, probe intent, and intermediate data prefixes (drv_, out_, merge_, _tmp_)
- **Implementation gaps**: missing decomposition seams for config/systemd, hierarchy interaction, migration guardrails, BYPASS mapping, and the reusable four-slice template

Before retiring [`intent-prefix-system.md`](intent-prefix-system.md), all items in section 2 must be absorbed into [`pipeline-and-intent-prefix-memo.md`](pipeline-and-intent-prefix-memo.md) or [`ARCHITECTURE.md`](/ARCHITECTURE.md).
