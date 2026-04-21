# Compfuzor Architecture Draft

This is a draft architecture document for compfuzor.

It is intentionally low-code and low-constraint. It describes the model we are
converging on without freezing exact implementation shape.

## Status

- Draft, evolving.
- This document is intended to replace memo-style design notes over time.
- Existing memos are still useful as working history.

## Why This Exists

Compfuzor has grown powerful conventions, but some terminology has mixed levels
of abstraction (pipeline timing, file naming, fact naming, and subsystem
responsibility). This draft separates those concerns so contributors and agents
can reason clearly.

## Core Model

Compfuzor has two big dimensions:

- **Pipeline phase**: when work runs.
- **Entity facets**: what a named thing is and how it should behave.

The same subsystem can appear in multiple phases.

## Prefix Family Notes

- Prefix family names remain important and should stay visible.
- `kind` is the prefix family identity (for example `syn`, `fn`, `probe`).
- File/data location metadata should not dominate identity.

## Record Shape

There is no separate envelope taxonomy layer.

- A handoff key like `_syn_<domain>` is still `kind:syn`.
- Record-key patterns are an optional field attached to a `kind`, not a new
  kind.

## Facet Catalog

The table below is the architecture vocabulary. It is not a hard schema yet;
it is the intended direction.

| Facet | Example | Purpose | Description | Cardinality |
|---|---|---|---|---|
| `kind` | `kind:syn` | primary family identity | Semantic lineage of an entity; this should be the first discriminator when classifying behavior. | `1` |
| `record` | `record:_syn_<domain>` | optional handoff key shape | Optional record-key pattern associated with a `kind` for cross-step handoff. This is metadata on a kind, not a separate taxonomy class. | `0..1` |
| `origin` | `origin:fact-key` | provenance metadata | Where the entity lives (`task-file`, `fact-key`, and future surfaces if needed). This is metadata, not primary identity. | `1` |
| `phase` | `phase:compile.synthesis` | runtime timing | Pipeline point(s) where this entity is evaluated, synthesized, or applied. | `1..n` |
| `role` | `role:synthesis` | behavioral responsibility | Responsibility tags for reasoning and review. Often multi-valued (`role:synthesis`, `role:handoff`). | `1..n` |
| `apply` | `apply:get-urls` | target domain | Domain target(s) the entity concerns. Can be broad or narrow (`filesystem`, `repo`, `get-urls`). | `0..n` |
| `effect` | `effect:host.fs` | side-effect profile | Effect model rather than implementation detail (`none`, `host.fs`, `host.repo`, `network`). | `1..n` |
| `matcher` | `matcher:regex(^_syn_[a-z0-9_]+$)` | predicate checking | Machine-checkable classification rule for linting, review, and agent guidance. | `0..1` |

## Phase Vocabulary (Draft)

Use `phase`, not `stage`.

Current high-level phase names:

- `phase:compile`
- `phase:user-context`
- `phase:repo-apply`
- `phase:fs-apply`
- `phase:extras-apply`
- `phase:post-run`

Optional nested names are allowed when useful (`phase:compile.foundation`,
`phase:compile.synthesis`).

## Domain Activation Contract (Draft)

Each domain should expose one shared activation contract to decide whether
downstream work should run.

Required per-domain facts:

- `<DOMAIN>_REQUESTED`: input exists and is non-empty for that domain.
- `<DOMAIN>_BYPASSED`: effective bypass resolution (`<DOMAIN>_BYPASS|default(false)|bool`).
- `<DOMAIN>_VALID`: contract validation passed.
- `<DOMAIN>_ACTIVE`: `<DOMAIN>_REQUESTED and not <DOMAIN>_BYPASSED and <DOMAIN>_VALID`.

Optional diagnostic fact:

- `<DOMAIN>_STATUS`: mapping with at least `requested`, `bypassed`, `valid`,
  `active`, and optional `reasons` list.

Execution rules:

- `vars_*` computes activation facts during `phase:compile.foundation`.
- `fn_*` and `gen_*` run only when `<DOMAIN>_ACTIVE`.
- apply tasks (`repo_*`, `fs_*`, `bins*`, extras) run only when
  `<DOMAIN>_ACTIVE`.
- if `<DOMAIN>_REQUESTED` and not `<DOMAIN>_BYPASSED` but invalid, fail early
  in compile phase.

This keeps skip/fail behavior consistent across domains and removes ad hoc
`when` drift.

## Relationship Examples

- `gen_` can be modeled as:
  - `kind:syn`
  - `record:_syn_<domain>`
  - `origin:task-file`
  - `role:synthesis`

- `_syn_<domain>` can be modeled as:
  - `kind:syn`
  - `record:_syn_<domain>`
  - `origin:fact-key`
  - `role:synthesis` `role:handoff`

This expresses is-a relationships without overloading one field.

## Guidance For Contributors And Agents

- First identify `kind`.
- Then identify `record` (if needed) and `origin`.
- Then assign `phase` and `role`.
- Finally document `apply` and `effect`.

If two entities share `kind` but differ in `origin`, that is expected.

## Non-Goals (For This Draft)

- Not freezing exact file renames yet.
- Not defining a full linting implementation yet.
- Not requiring immediate migration of all existing task files.

## Next Steps

- Align docs to use `phase` consistently.
- Keep memo docs as references but point architecture decisions here.
- Add lightweight checks later for `matcher` and facet consistency.
- Adopt domain activation contract in pilot domains (`GET_URLS`, `KERNEL`) and
  document migration slices in [`doc/prefix.codex.md`](/doc/prefix.codex.md).
