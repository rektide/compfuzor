---
type: SeamDecision
title: Validate the native closure at the existing CONFIG commit boundary
description: Retain legacy per-recipe validation and add a post-candidate transaction hook plus explicit symlink-output staging.
resource: /design/keybindings/commit-seam0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-01 }
verified: { by: unverified }
sources:
  - resource: /files/config-run.sh
    title: Existing candidate production and sole commit/rollback implementation
  - resource: /design/keybindings/implementation0.gpt61sol.md
    title: Accepted first implementation checkpoint, with provisional interfaces
stale_after: 2026-11-01
---

# Bounded compatible extension

The parent prefers native closure validation at the existing CONFIG commit
boundary, not committing fragment assembly and then implementing another
transaction around roots or delivery. A processor-only adapter is insufficient:
while each processor runs, later candidates do not yet exist, and ordinary file
inputs still address live outputs. A root validator inspecting those paths would
validate the old configuration.

Keep immediate legacy `validate` commands and the same commit/rollback loop.
Retain every produced candidate until transaction cleanup, even unchanged ones.
After production and existing per-recipe validation, write a versioned JSON map:

```json
{"version":1,"candidates":[{"name":"root","output":"/consumer/root","candidate":"/private/candidate","link":null}]}
```

An optional spec-level `transaction_validate` shell command runs once with
`CONFIG_CANDIDATES_FILE`, `CONFIG_TRANSACTION`, `CONFIG_SPEC` and `CONFIG_MODE`
(`apply`, `check`, `stdout`). Zero means proceed; nonzero stops before publication
or stdout. It can prepare a mirrored validation layout inside the private
transaction, but must not modify live state or candidate bytes. This is trusted
validator code, not a sandbox or a new scheduler. No hook means legacy behavior
and output ordering remain unchanged. Stdout still selects exactly one recipe;
all modes validate before returning their bytes/drift/publication result.

A native closure validator can recursively parse includes, capture referenced
noncandidate files, and rewrite references **in validation copies only** to the
mirrored staged layout. It uses map entries whenever an include targets a selected
output. Live candidate roots keep effective live include paths. Root/source
snapshot guards fail on detected concurrent changes before commit; no cross-process
locking or check-to-commit race elimination is claimed.

# Delivery at the same boundary

Add optional per-recipe `link: /absolute/target` for an explicitly staged symlink
output. Its processor still writes the target's captured bytes to its one candidate
for validation. The existing staging loop creates a private sibling symlink instead
of copying candidate bytes; the same backup/move/rollback loop publishes it.
Ordinary outputs remain regular files, preserve existing regular-file modes, and
default to 0600. Link drift compares the directory-entry target, not just bytes.
The adapter must ensure the candidate bytes correspond to the selected target and
detect source changes. This does not create an executable-output feature.

TypeScript orchestration captures YAML/native sources, pure-renders required
material, chooses direct/copy/link plus assemble/seed/refresh policy, and creates
ordinary single-output recipes over private captured inputs. Missing-copy seeding
and refresh are planned candidates, not preparatory live writes. A newly rendered
definition can therefore back a newly copied or linked consumer file without a
dependent-candidate DAG: all bytes are prepared explicitly before invoking CONFIG.
Definition outputs precede placement outputs, and root publication comes last.
Runtime-expanded recipes may explicitly select an existing deployed `leaf` path
(for example the shared concat processor). The legacy per-name leaf remains the
default. This avoids installing dynamic per-binding executable wrappers merely
to copy already captured inputs; it is explicit spec binding, not PATH discovery.

Shared CONFIG block assembly must provide explicit contribution IDs and comment
markers, preserve unmanaged text, and use adopted insertion areas. A readable
Umbriel template places baseline first, the managed insertion area inside its
single `files` array, then personal references. Arbitrary existing include tables
without the declared insertion area fail rather than acquiring another table.

# Limits and evidence to obtain

- One existing CONFIG commit; no another rollback executor for native artifacts.
- Hook failure, late processor failure and commit failure preserve old outputs,
  including symlink topology; check/stdout do not seed or refresh live copies.
- Reassembly consumes edited local copies. Refresh deliberately replaces them.
- Explicit native user files take the same selection/validation path as generated
  bodies; disabled registration state survives a coherent batch operation.
- Reject duplicate IDs, normalized/physical placement aliases and root collisions
  before writes. Source YAML IDs are authoritative; filenames are provenance only.
- No stale-file pruning, no live deployment, no broad Vicinae cutover, no Effect work.

This seam is small enough to implement compatibly. Full crash atomicity across
files, source mutation after validation, concurrent installations and filesystem
durability remain outside the current runner's guarantees.
