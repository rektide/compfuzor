---
type: Review
title: Read-only runtime catalog review
description: Independent validation of the attributed legacy catalog compiler, materialization, and TypeScript inspector.
resource: /design/config-anneal/catalog-review0.gpt6.md
tags: [compfuzor, runtime, catalog, review, attribution]
status: draft
generated: { by: model:gpt6, at: 2026-09-14 }
verified: { by: model:gpt6, at: 2026-09-14 }
stale_after: 2026-10-14
sources:
  - id: execution-model
    resource: /design/config-anneal/execution-model0.gpt6.md
    title: Contributed flows and execution policy
  - id: reviewed-tip
    resource: jj:6edbf14054bd9e8002412f4ae8079199ea7ba412
    title: Read-only catalog implementation tip
---

# Read-only runtime catalog review

## Verdict

The slice has the right observational boundary: generated descriptors explicitly
retain `legacy-shell` authority and `catalogOnly`, the runtime does not dispatch
actions, and the catalog command is installed only when the omnibus Node runtime
is already present. Contributor references, recursive compositor contributor and
earliest-phase derivation, `01–99` placement, one invocation per file, domain
resource references, and `isolatedDeclarations` all have credible foundations.

It is **not ready to accept**, however. Generated catalog files are not actually
materialized, and catalog selection is not closed over the catalog's declared
flow membership. The latter makes stale files authoritative and also breaks
cross-flow tombstones.

## Findings

### High — Catalog and compiled invocation files are never materialized

[`compfuzor.includes`](/tasks/compfuzor.includes#L109-L126) freezes
`_ARTIFACTS` before `gen_runtime_catalog.tasks` appends its `ETC_FILES` records.
The filesystem writer later reads entries from that frozen snapshot
([`fs_hierarchy.tasks`](/tasks/compfuzor/fs_hierarchy.tasks#L20-L36)), not the
subsequently updated variable. The catalog task does append the records
([`gen_runtime_catalog.tasks`](/tasks/compfuzor/gen_runtime_catalog.tasks#L14-L18)),
but only its directly read `ETC_DIRS` survive.

An isolated Ansible probe using this exact ordering completed successfully and
created `etc/compfuzor-runtime/workflows/{compiled,site}/`, but created neither
`catalog.json` nor any compiled JSON file. Existing tests miss this: the LINKS
integration test inspects `_RUNTIME_CATALOG.files` in memory without running the
ETC writer ([`links.test.py`](/tests/integration/links.test.py#L58-L70)), while
the runtime test hand-writes its fixture files
([`runtime_catalog.test.py`](/tests/integration/runtime_catalog.test.py#L73-L75)).

### High — Directory scanning bypasses catalog membership and admits stale state

The compiler emits an explicit flow-to-ID index
([`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py#L270-L278)),
and the TypeScript parser reads it
([`runtime.ts`](/files/catalog/runtime.ts#L107-L114)), but `loadFlow` ignores it
and selects every matching JSON file found in `compiled/` and `site/`
([`runtime.ts`](/files/catalog/runtime.ts#L175-L205),
[`runtime.ts`](/files/catalog/runtime.ts#L207-L254)). Compfuzor deliberately does
not prune undeclared artifacts, so a compiled file left by an earlier render is
reported as current intent. A new regular site descriptor with no compiled ID is
also accepted at lines 237–253, contrary to the requested placement/tombstone-only
shadowing boundary. Flow results therefore are not the deterministic validated
catalog described by the execution model.

Use the catalog's declared IDs as the closed compiled selection set, reject
unindexed compiled files (or report them separately as stale), and require every
site record in this slice to shadow one declared compiled ID.

### High — A tombstone for one flow breaks every other flow

`loadFlow` first filters compiled records to the requested flow, but processes
all site tombstones without a flow discriminator. A valid install tombstone is
therefore "unknown" while loading build
([`runtime.ts`](/files/catalog/runtime.ts#L207-L235)). A probe with one build
entry, one install entry, and an install tombstone produced:

- `flow install`: success, empty result;
- `flow build`: exit 2, unknown compiled contribution;
- `flows`: exit 2.

Resolve tombstones against a global declared-ID index before projecting one
flow, or retain enough indexed metadata to route a minimal `{id,state}`
tombstone. Add a multi-flow test; the current single-flow fixture cannot expose
this ([`runtime_catalog.test.py`](/tests/integration/runtime_catalog.test.py#L51-L55)).

### Medium — Validation is permissive where the catalog claims strictness

Malformed contributor and flow-entry arrays silently lose non-string members
through `strings()` ([`runtime.ts`](/files/catalog/runtime.ts#L75-L79)); flow
descriptors are otherwise accepted without validating version, invocation,
scope, contributors, native/source shape, or catalog membership. `execution` is
only cast after an object check ([`runtime.ts`](/files/catalog/runtime.ts#L88-L114)).
On the compiler side, status `args` is coerced with `list(...)`
([`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py#L246-L265));
an accidental string `"--json"` becomes six character arguments. Reject bad
contract data rather than filtering or coercing it, especially before external
handlers are ever executable.

## Architecture notes

- **Authority:** Correctly catalog-only; no catalog path executes a handler.
- **Runtime dependency:** Correctly conditional. `_catalog_bins` is empty unless
  `compfuzor-runtime.mjs` already exists in BINS
  ([`gen_runtime_catalog.tasks`](/tasks/compfuzor/gen_runtime_catalog.tasks#L19-L30)).
- **Legacy flow fidelity:** Top-level generated shell roots are catalogued as
  their direct calls, while recursive traversal derives contributors and the
  earliest legacy phase ([`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py#L78-L129),
  [`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py#L228-L245)).
  This preserves shell execution authority rather than flattening nested
  compositors into a second runner.
- **Resources:** CONFIG, Zim, and LINKS remain references to their domain specs,
  not embedded universal plans
  ([`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py#L132-L146)).
- **Placement:** Two-digit `01–99` filename validation and phase derivation are
  sound for selected records. Same-ID semantic comparison correctly excludes
  placement metadata, but should run only after closed-set ID validation.

## Verification

Passed:

- `pnpm check` (format, lint, `tsgo --noEmit` with `isolatedDeclarations`)
- `pnpm build`
- all filter-plugin and lookup-plugin test scripts
- focused catalog compiler, runtime catalog, LINKS, status-argument,
  compositor, cfmerge-BINS, LINKS-status, and systemd-LINKS integration tests
- `ansible-playbook --syntax-check jujutsu.src.pb`

Additional probes reproduced all three high-severity findings. No implementation
files were changed as part of this review.

## Cross-references

- [`execution-model0.gpt6.md`](/design/config-anneal/execution-model0.gpt6.md)
  defines the catalog-only authority, compiled/site model, lexical ordering, and
  first-checkpoint acceptance criteria used here.
- [`doc/bins.md`](/doc/bins.md) describes the legacy compositor hierarchy whose
  actual direct-call order remains authoritative in this slice.
- [`doc/arch.md`](/doc/arch.md) explains artifact compilation and synthesis; its
  materialization boundary is the source of the ordering defect above.
