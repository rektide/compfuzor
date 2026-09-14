---
type: Review
title: Read-only runtime catalog fix review
description: Follow-up validation of catalog materialization, closed-set flow loading, validation, and direct CONFIG compilation.
resource: /design/config-anneal/catalog-review1.gpt6.md
tags: [compfuzor, runtime, catalog, review, config]
status: draft
generated: { by: model:gpt6, at: 2026-09-14 }
verified: { by: model:gpt6, at: 2026-09-14 }
stale_after: 2026-10-14
sources:
  - id: prior-review
    resource: /design/config-anneal/catalog-review0.gpt6.md
    title: Read-only runtime catalog review
  - id: materialization-and-selection-fix
    resource: jj:ef185aacd0e5b9e956e86a486fda5ffae41b3050
    title: Honor declared flow inventory and materialize files
  - id: direct-config-compiler
    resource: jj:dc44e0ba4fcd2624ac8093218c50456d2b68f53b
    title: Emit final CONFIG runtime model directly
  - id: runtime-build
    resource: jj:19aed63e33c9b3e2ed81e80ad0aa8647107ad2b3
    title: Refresh attributed catalog runtime
---

# Read-only runtime catalog fix review

## Verdict

The four findings in the initial review are substantively fixed:

- the second artifact compilation makes late catalog ETC records visible to the
  filesystem writer;
- catalog flow membership is now a closed compiled set, stale valid descriptors
  are ignored, missing declared descriptors fail, and undeclared site records
  fail;
- minimal tombstones route through the global declared-ID map without breaking
  other flows;
- string arrays are strict and a scalar Python status argument remains one
  argument.

The direct CONFIG compiler simplification also passes its focused CONFIG and Zim
coverage, and rebuilding the checked runtime is byte-for-byte deterministic.

The slice still cannot be accepted because a new end-to-end test found one
**high-severity integration defect**: the runtime rejects every normal filename
emitted by the compiler.

## Residual finding

### High — Runtime filename parsing rejects compiler-generated filenames

The compiler emits names in the form
`NN-FLOW-SEQUENCE-SLUG.json`, for example
`50-build-001-build-rust-sh.json`
([`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py#L108-L129)).
The runtime parses the flow with the greedy group
`([a-z0-9-]+)` and then compares that group with the expected flow
([`runtime.ts`](/files/catalog/runtime.ts#L145-L152)). For the example, the
captured flow extends through the sequence and most of the slug rather than
being `build`.

A full `jujutsu.src.pb` run through [`compfuzor.includes`](/tasks/compfuzor.includes)
successfully materialized `catalog.json` and four compiled descriptors. The
checked-in runtime then failed both real flows:

```text
flow filename .../50-build-001-build-rust-sh.json does not match descriptor flow build
flow filename .../40-install-001-install-config-sh.json does not match descriptor flow install
```

This escaped because the runtime integration fixture uses hand-authored names
such as `50-build-tool.json` and `95-install-links.json`
([`runtime_catalog.test.py`](/tests/integration/runtime_catalog.test.py#L73-L89)),
while the LINKS integration proves only that generated files physically exist
([`links.test.py`](/tests/integration/links.test.py#L113-L117)). Neither passes a
compiler-generated filename into `loadFlow`.

Match the already-known expected flow literally after the two-digit index, or
otherwise make the filename grammar unambiguous. Add one end-to-end assertion
that invokes the built catalog runtime against files produced and materialized
by Ansible.

## Fix validation

### Materialization and ordering

The refresh after catalog synthesis
([`compfuzor.includes`](/tasks/compfuzor.includes#L109-L130)) preserves the first
snapshot for LINKS compilation and replaces `_ARTIFACTS` before filesystem
materialization. The full-include probe completed successfully and physically
created `catalog.json` plus four workflow files. The LINKS integration also
passed, confirming that the second snapshot does not invalidate `_LINK_PLAN`.

### Closed-set and site behavior

The runtime constructs a global ID-to-flow map, selects only IDs declared for
the requested flow, checks missing compiled members, rejects undeclared site
records, and routes tombstones before per-flow projection
([`runtime.ts`](/files/catalog/runtime.ts#L201-L298)). Focused probes confirmed:

- stale valid compiled descriptor: ignored;
- install tombstone while loading all flows: build remains available;
- declared descriptor missing on disk: rejected;
- undeclared site descriptor: rejected;
- malformed flow entry string array: rejected.

Descriptor version, flow, invocation object, contributor array, duplicate ID,
and lexical placement checks now provide an appropriate read-only baseline.

### CONFIG and build artifact

The direct CONFIG compiler now emits the internal runner/processors directly
and no longer relies on the deleted translation pass. Canonical input
list/status/enable/disable behavior passed the graph and consumer-toolkit
integrations, and focused Zim lifecycle, wrapper-isolation, and canonical-donor
tests passed. `pnpm build` reproduced the committed
`build/runtime/compfuzor-runtime.mjs` hash exactly.

## Verification

Passed:

- `pnpm check`
- `pnpm build`, with identical runtime hash before and after
- every filter-plugin and lookup-plugin test script
- catalog compiler and runtime fixtures
- full LINKS integration with physical catalog materialization
- related compositor, cfmerge-BINS, LINKS status, status arguments, and systemd
  LINKS integrations
- focused CONFIG compiler/context, graph, and consumer-toolkit tests
- focused Zim consumer, demo-wrapper, and remote/canonical-donor tests
- `ansible-playbook --syntax-check jujutsu.src.pb`
- side-effect-contained full `jujutsu.src.pb` include probe with repository,
  package, BINS, LINKS, systemd thunk, and module effects bypassed

Failed as expected from the residual finding:

- built runtime `catalog ... flows` against the full-include probe's generated
  and materialized catalog.

No implementation files were changed for this review.

## Cross-references

- [`catalog-review0.gpt6.md`](/design/config-anneal/catalog-review0.gpt6.md)
  records the original four findings now verified as fixed.
- [`execution-model0.gpt6.md`](/design/config-anneal/execution-model0.gpt6.md)
  requires generated one-invocation files and runtime validation to form one
  interoperable catalog, which the remaining filename mismatch prevents.
