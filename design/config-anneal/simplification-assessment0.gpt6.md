---
type: DesignAssessment
title: Configuration simplification tactical assessment
description: Rates the current simplification proposals and defines a behavior-preserving one-artifact runtime cutover.
resource: /design/config-anneal/simplification-assessment0.gpt6.md
tags: [compfuzor, config, runtime, vite-plus, simplification, annealing]
status: draft
generated: { by: model:gpt6, at: 2026-09-13 }
verified: { by: unverified }
stale_after: 2026-10-13
sources:
  - id: simplification-plan
    resource: /doc/config/simplification.md
    title: Simplifying Compfuzor configuration internals
  - id: consumer-contract
    resource: /doc/config/consumer-toolkit.md
    title: Consumer configuration toolkit
  - id: runtime-compilers
    resource: /library/filter_plugins/runtime_bundles.py
    title: Runtime artifact compiler helpers
---

# Configuration simplification tactical assessment

## Situation and requested direction

Compfuzor's CONFIG, config-remote, LINKS, and Zim runtime behavior is currently
implemented in domain-grouped TypeScript but emitted as four self-contained
Vite+ artifacts. The requested tactical step is narrower than the full
[simplification plan](/doc/config/simplification.md): assess that plan candidly,
then replace those four products with one built `compfuzor-runtime.mjs` multicall
artifact without changing CONFIG context or install semantics. The source should
remain separated by domain; a minimal root dispatcher should select existing
domain implementations.

A useful follow-up research prompt is: *Which conceptual interfaces can be
deleted from Compfuzor configuration without moving equivalent complexity into
controller compilation, status projection, or deployment ownership? Evaluate
using generated-plan snapshots and target-side behavioral evidence.*

The model suffix is `gpt6`, the most specific active model-family identity
available to this session.

## Rating method

Scores run from 1 (low) to 5 (high). Difficulty and impact/risk score the size
of the implementation and the blast radius of a mistake, respectively. “Model
simplification” asks whether users or maintainers have fewer concepts and
translations to understand; an implementation-only improvement may still be
worth doing, but should not be sold as a simpler domain model.

| Proposal | Value | Difficulty | Impact/risk | Simplification kind | Verdict |
|---|---:|---:|---:|---|---|
| 1. Replace Zim token substitution | 3 | 3 | 4 | Genuine model simplification, modest in size | Prototype against the exact upstream CLI before accepting |
| 2. Emit the final CONFIG command model directly | 5 | 4 | 5 | Strong model and implementation simplification | Best structural deletion; do separately with snapshots |
| 3. Finish the Vite+ deployment boundary | 4 | 4 | 4 | Mostly implementation/deployment simplification | Continue one independent domain at a time |
| 4. Reduce spec overlap | 2 now | 4 | 5 | Depends on the slice; easy to make the model worse | Defer as proposed |
| 5. Keep output concise | 4 | 2 | 2 | Usability, not model simplification | Worth incremental observational changes |
| 6. Deliberately prune migration residue | 3 | 2 | 3 | Operational cleanup, not model simplification | Completed appropriately; retain no-auto-prune policy |
| Requested one-artifact multicall cutover | 3 | 3 | 3 | Implementation/deployment simplification only | Do now with explicit alias and co-ownership rules |

## Proposal-by-proposal assessment

### 1. Delete the custom Zim substitution engine

The proposal removes a real second template vocabulary. The current projection
has token cardinality, unknown-token, replacement, and newline rules in
[`activation.ts`](/files/zim/activation.ts), so using the transformation already
owned by `block-in-file` would reduce the conceptual surface.

The value is nevertheless only moderate. The custom implementation is small and
deterministic; status currently computes expected bytes in memory. The proposed
replacement adds environment projection plus a temporary install/read cycle to
recover expected bytes. That can trade obvious local code for more subprocess,
temporary-file, quoting, and version-coupled behavior. The negative-lookahead
exclude expression and non-recursive mode must be verified against the exact
deployed `block-in-file` release, not inferred from its README. Paths containing
quotes, literal dollar expressions, malformed templates, and byte-exact final
newlines are high-impact cases.

**Verdict:** conceptually sound, but accept only if a focused prototype deletes
more rules than it introduces and install/status share one upstream projection
operation. An upstream render-only operation would make this clearly better.

### 2. Stop emitting and rewriting the old CONFIG command model

This is the plan's highest-value proposal. [`config_compile.py`](/library/filter_plugins/config_compile.py)
emits obsolete public wrappers, while [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
recognizes their exact names and command strings, renames some, rewrites others,
and drops the rest. Removing `_internalize_config_bins()` deletes both a
translation and the need to understand an intermediate command model that no
target receives.

The risk is also highest because that adapter currently carries behavior:
bypass-neutral internals, processor locations, fixed action aliases, status
registration, and the canonical no-context assembly path. This should not be
combined with the omnibus runtime cutover. Exact before/after compiled BINS,
DIRS, status, and spec snapshots are the right proof.

**Verdict:** prioritize as the next structural change, but not in this tactical
artifact patch. It genuinely simplifies both the model and implementation.

### 3. Finish the Vite+ deployment boundary

The target-side rule “built JavaScript, not TypeScript source” is valuable: it
makes controller/target responsibility testable and avoids requiring target
loaders to understand repository source layout. Moving the remaining kernel,
Repart/Mkosi, and MCP surfaces is not one uniform change, however. Embedded
Mkosi use and status-script invocation differ materially from ordinary BINS
deployment.

**Verdict:** retain the domain-at-a-time order. This is mostly implementation
and delivery simplification, not CONFIG model simplification. Do not infer from
a shared bundler that the domains should share APIs or lifecycle semantics.

### 4. Reduce specification overlap only after the deletions

The proposal is correctly cautious. `config.spec.json`, `zim.spec.json`, and
`links.json` encode different ownership and lifecycle contracts. A shared path
selector may delete duplicated parsing rules; a universal plan would instead
couple domains and enlarge the model.

**Verdict:** low present value and high semantic risk. Reassess after direct
CONFIG emission and Zim projection work exposes what duplication remains.
Sharing a helper is not itself model simplification unless it also removes a
concept visible at the domain boundaries.

### 5. Keep user-facing output concise

The listed changes improve operability and discovery with limited blast radius.
They do not simplify the underlying model: inventory, context, recipe, and
representation still exist. That distinction is healthy—observability should
describe the model rather than reshape it for prettier output.

**Verdict:** pursue in focused changes with stdout and exit-code fixtures. Avoid
adding alias combinations or an interactive layer.

### 6. Deliberately prune proven migration residue

The recorded prune is useful operational hygiene and the procedure preserves
the project's no-automatic-prune contract. It does not simplify current runtime
semantics; it removes unreachable historical files and reduces deployment
confusion.

**Verdict:** complete. Keep future pruning explicit, enumerated, and evidenced;
do not generalize it into reconciliation or ownership storage.

## Tactical omnibus runtime design

### What changes—and what does not

Vite+ should have one entry and emit exactly:

```text
build/runtime/compfuzor-runtime.mjs
```

Deployed packages should contain that one regular built file plus stable aliases:

```text
bin/compfuzor-runtime.mjs
bin/config/command.mjs      -> bin/compfuzor-runtime.mjs
bin/config-remote.mjs       -> bin/compfuzor-runtime.mjs
bin/links/links.mjs         -> bin/compfuzor-runtime.mjs
bin/links.mjs               -> bin/compfuzor-runtime.mjs
bin/zim/install.mjs         -> bin/compfuzor-runtime.mjs
```

The six fixed CONFIG action symlinks continue to target
`config/command.mjs`; shell Zim commands continue to invoke
`zim/install.mjs`; internal shell processors and all JSON specs remain
unchanged. CONFIG's generic context precedence and alias parsing remain in its
domain module.

This cuts artifact count and duplicate bundled code, but it does **not** make
the four domains one model. The runtime dispatcher owns only invocation routing,
deployment-root discovery, and top-level error/exit conventions.

### Deployment ownership and deduplication

No new runtime-owner variable or persistent ownership database is needed. Every
subsystem that must work independently may contribute the identical
`compfuzor-runtime.mjs` copy record plus only its own stable aliases. The existing
`bins_generated` merge folds BINS records by `name` and preserves one position;
identical artifact claims therefore deduplicate naturally when CONFIG, LINKS,
and Zim coexist. This is compatible co-ownership, not arbitrary “first owner” or
“last owner” selection.

The artifact helper should be canonical so all claims use the same source,
raw/copy flags, and destination name. Tests must prove a composite Zim host has
one regular runtime file, all domain aliases resolve to it, and no `.ts`/`.py`
runtime leaks into the deployed tree. Standalone LINKS and CONFIG packages must
also remain complete.

### `argv[0]` and symlink aliases

Dispatching only on `basename(process.argv[1])` would regress CONFIG. Today a
caller can create an arbitrary symlink to `config/command.mjs` and use explicit
`--action` and `--context`; its basename intentionally reaches CONFIG's own
validation. Once every domain resolves to the same inode, `realpath()` alone
erases which domain alias was traversed.

The root dispatcher should therefore inspect the lexical invocation path and
follow its symlink chain without discarding intermediate targets. It can route
on the first recognized name/path in that chain while passing the original
basename to CONFIG and Zim. This preserves direct, chained, context-bearing, and
hostile CONFIG alias behavior. Exact stable names route config-remote, LINKS,
and Zim before the broad `config-*.sh` rule. A direct invocation of
`compfuzor-runtime.mjs` should require an explicit first domain word; unknown
aliases should fail rather than guess.

### Source boundaries

The omnibus entry should import small exported domain runners. Existing source
CLI files need thin main-module wrappers rather than self-executing when
imported: bundling several modules that each compare `argv[1]` with
`import.meta.url` can make all guards see the final bundle URL. Moving runner
logic into `config/runtime.ts`, `config-remote/runtime.ts`, `links/runtime.ts`,
and `zim/runtime.ts` preserves domain grouping while keeping the root dispatcher
minimal. It is explicitly preferable to merging domain implementations.

### Isolated declarations

The runtime sources already annotate exported function returns and exported
object types. A TypeScript native-preview probe with `--declaration
--isolatedDeclarations --noEmit` found one bounded first-party blocker: the
inferred default export in [`vite.config.ts`](/vite.config.ts). Dependency
declarations from Vite+/Vitest additionally require `skipLibCheck` under the
project's Node-only `lib` selection. The tactical patch can add an explicit
config export annotation, enable `declaration`, `isolatedDeclarations`, and
`skipLibCheck` with `noEmit`, and add explicit annotations to new exports.

## Acceptance evidence for the tactical patch

1. Vite+ emits one executable `.mjs` and no four legacy products.
2. Filter/compiler tests show independently complete CONFIG, config-remote,
   LINKS, and Zim aliases, with one compatible runtime claim after composition.
3. CONFIG direct, chained, arbitrary explicit, fixed-action, context, strategy,
   status, and error behavior remains covered.
4. config-remote mutation/rebuild rollback, LINKS standalone and composed
   delivery, and Zim install/import/status integration continue to pass.
5. Native TypeScript checking passes with isolated declarations; Vite+ format,
   lint/type-check, and build pass.
6. Python filter plugins compile and focused unit/integration tests pass.

## Cross-references

- [`simplification.md`](/doc/config/simplification.md) is the plan assessed here;
  its product contracts remain the guardrails.
- [`consumer-toolkit.md`](/doc/config/consumer-toolkit.md) defines the stable
  CONFIG command/context interface and currently documents the four products.
- [`log.md`](/doc/config/log.md) records the preceding Vite+ cutover and should
  receive a concise new deployment-boundary entry when this artifact ships.
- [`runtime_bundles.py`](/library/filter_plugins/runtime_bundles.py) is the
  natural canonical source of compatible runtime artifact claims.
- [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
  emits CONFIG's stable action aliases; its context/install semantics are out of
  scope for this cutover.
- [`zim_context_compile.py`](/library/filter_plugins/zim_context_compile.py)
  demonstrates why complete Zim hosts need CONFIG, LINKS, and Zim aliases while
  still requiring only one runtime artifact.
