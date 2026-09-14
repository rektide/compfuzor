---
type: ArchitectureReview
title: Opt-in catalog flow execution review
description: Independent review of the catalog executor and isolated Zim2/Mise2 experiments against the contributed-flow execution model.
resource: /design/config-anneal/flow-execution-review0.gpt6.md
tags: [compfuzor, runtime, catalog, execution, zim, mise, review]
status: draft
generated: { by: model:gpt6, at: 2026-09-14 }
verified: { by: model:gpt6, at: 2026-09-14 }
stale_after: 2026-10-14
sources:
  - id: execution-model
    resource: /design/config-anneal/execution-model0.gpt6.md
    title: Contributed flows and execution policy
  - id: reviewed-sequence
    resource: vcs:jj:ab2b00c6..08de0fd1
    title: Experimental deployments through authored aggregate fidelity
---

# Opt-in catalog flow execution review

## Verdict

The opt-in boundary is sound, and the compiler now preserves Mise2's authored
aggregate body without double-running its child. Fixed descriptor arguments,
mutation short-circuiting, status continuation/folding, closed catalog
membership, site tombstones, alias timing, and checked-in bundle freshness also
held in review.

The executor is **not ready for live Zim2/Mise2 mutation**. Two high-severity
containment/fidelity defects allow execution outside the selected deployment:
decomposed leaves inherit an ambient foreign `DIR`, and a lexically contained
handler may be a symlink to an executable outside the deployment. Signal
termination can additionally leave a mutating child alive. The current
render/dry-run evidence does not exercise these boundaries, and the experiments
share production host targets, so dry-run is the correct present limit.

## Findings

### High — decomposed flows lose the deployment-rooted `DIR` boundary

[`files/flow/runtime.ts:83-87`](/files/flow/runtime.ts#L83-L87) spawns each leaf
with the runner's inherited environment. The shell compatibility root normally
overwrites `DIR` from its own real path
([`files/_bin:26-31`](/files/_bin#L26-L31)), while an ordinary leaf's env helper
only supplies `DIR` when it is absent. The compiler deliberately decomposes a
pure generated root into its immediate children
([`runtime_catalog.py:258-273`](/library/filter_plugins/runtime_catalog.py#L258-L273)),
therefore removing the boundary that made legacy aggregate execution immune to
a caller's foreign `DIR`.

This is concrete in the rendered Zim2 deployment. With
`DIR=/definitely/wrong`, direct `install-apt.sh --help` failed while trying to
`cd /definitely/wrong`; the catalog flow would spawn that same leaf. More
dangerously, an existing but foreign `DIR` can redirect env loading and
DIR-relative effects rather than fail. Status reporters have the same problem.
Mise2 happens to invoke its authored aggregate root opaquely, so that specific
install flow retains root establishment, but this is not a general safeguard.

Before mutation, the executor should establish the selected deployment context
for every child (at minimum a runner-owned `DIR`, with an explicit decision for
other ambient Compfuzor variables), or invoke a deployment-rooted compatibility
boundary whose semantics are demonstrably equivalent.

### High — executable containment does not resolve symlinks

[`files/flow/runtime.ts:71-80`](/files/flow/runtime.ts#L71-L80) compares only the
lexically resolved configured path to the deployment directory. `spawn()` then
follows any final or intermediate symlink. A contained probe placed
`bin/escape.sh` inside a deployment as a symlink to a sibling external script;
the flow executed it and returned zero. Absolute paths outside the deployment
are correctly rejected, and absolute paths inside it pass, but symlink targets
are not contained.

This violates the catalog authority's stated restriction to deployment-owned
handlers and the design's refusal to discover arbitrary executables
([`execution-model0.gpt6.md:530-543`](/design/config-anneal/execution-model0.gpt6.md#L530-L543)).
Resolve the deployment and executable through filesystem reality before spawn,
then check containment. The residual check/use race should be documented if an
open-by-handle execution mechanism is out of scope.

### High — terminating the runner can leave mutation running

[`files/flow/runtime.ts:83-88`](/files/flow/runtime.ts#L83-L88) neither forwards
signals nor arranges child-process-group cleanup. In a contained probe, sending
`SIGTERM` to the Node runner ended the runner with `SIGTERM` while its long-lived
shell child remained alive. That makes interruption ambiguous: the operator
loses the authority process while the selected mutation may continue.

The downstream process design already calls for detached process groups and
signal forwarding
([`effect-design0.glm53.md:185`](/design/config-anneal/effect-design0.glm53.md#L185)).
The catalog executor needs equivalent behavior before it becomes mutation
authority; this should not wait for an Effect migration.

### Medium — final scheduling uses locale collation, not lexical filename order

Layer reads use code-unit `.sort()`, but the effective schedule is re-sorted
with `localeCompare()`
([`files/catalog/runtime.ts:303-305`](/files/catalog/runtime.ts#L303-L305)). This
does not implement the model's observable complete lexical filename order
([`execution-model0.gpt6.md:361-383`](/design/config-anneal/execution-model0.gpt6.md#L361-L383)).
For example, code-unit order placed `a-.json`, `a0.json`, `aA.json`,
`a_.json`, `aa.json`, while the local `localeCompare` order placed `_`, `-`,
`0`, lowercase, uppercase. Generated filenames are narrow enough to mask much
of this, but site filenames intentionally control placement and accept any
non-empty suffix. Use one specified byte/code-unit lexical comparator for both
layers and test punctuation/case behavior.

### Medium — Zim2/Mise2 isolate deployment names, not live host effects

The playbooks are exact production copies except `TYPE`, the execution flag,
and Zim2's source alias. Their deployment roots and attribution are distinct
(`zim2-main`, `mise2-main`), but their operative host destinations are not:

- Zim2 retains the production `$HOME/.cache/zim`, `$HOME/.cache/zim-env`, Zsh
  configuration outputs, and module/cache behavior
  ([`zim2.opt.pb:8-17`](/zim2.opt.pb#L8-L17)).
- Mise2 retains production `.bashrc`, `.bash_profile`, legacy Zsh block removal,
  and global Mise settings mutation
  ([`mise2.opt.pb:35-72`](/mise2.opt.pb#L35-L72)).
- [`files/zim2`](/files/zim2) is a symlink to `files/zim`, so implementation
  source is deliberately shared rather than experimentally isolated.

This is acceptable for render-only comparison, but these are not safe live
execution sandboxes. An accidental non-dry invocation can change the same user
state as production and may add differently named Mise2 blocks. Keep the
experiments explicitly dry-run-only until their target HOME/XDG/cache/settings
surfaces are redirected, or state plainly that they are canary deployments
rather than contained execution experiments.

### Medium — execution evidence omits the dangerous compatibility boundaries

[`tests/integration/catalog_flow.test.py`](/tests/integration/catalog_flow.test.py)
proves successful install ordering, dry-run, status `1` continuation, status
`2` not-applicable continuation, and disabled-authority refusal. Despite its
docstring, it does not create a failed mutation, and it does not cover:

- mutation short-circuit and preservation of exit `1` versus `2`;
- status `exit2: error` continuation/folding;
- absolute path rejection or symlink escape;
- ambient foreign `DIR` and wrapper bypass behavior;
- signal forwarding and child cleanup;
- flow CLI rejection of broadcast arguments;
- execution after site reorder/tombstone;
- authored-root body plus `run_all` through the runtime, rather than compiler
  shape alone;
- missing/non-executable status reporters (legacy `status.sh` skips them at
  [`files/status/status.sh:27-31`](/files/status/status.sh#L27-L31), while the
  executor turns spawn failure into a flow-level error).

The scratch renders are useful compile/materialization evidence. They show Zim2
as apt then complete Zim install, Mise2 as one opaque authored root, correct
fixed Zim status arguments, authority metadata, aliases, and bundle bytes. They
only dry-run the real deployments, however. The isolated fixture's generic
three-argument script does not validate generated wrappers, bypass guards,
deployment identity, or domain effects. The evidence is therefore adequate for
catalog shape and dry-run UX, not for promoting mutation authority.

## Behaviors that held

| Area | Review result |
|---|---|
| Default versus opt-in | `RUNTIME_FLOW_EXECUTION` defaults false; default catalogs remain `legacy-shell`/catalog-only, and only explicit true adds the flow alias and catalog authority. |
| Ordinary Node dependency | A deployment without the omnibus runtime still receives data-only catalog artifacts, not runtime BINS. Existing runtime consumers receive only the catalog alias. Opt-in explicitly adds the runtime. |
| Authored aggregate fidelity | Non-empty `early/generated/content/exec/execs/late` causes the generated root to be invoked once. Its `run_all` remains inside that wrapper, avoiding omission and duplicate child execution. Mise2 rendered exactly this shape. |
| Pure aggregate decomposition | Only top roots are lifted; generated children are excluded as roots. Immediate subsystem compositors remain opaque commands, preserving their nested order and avoiding recursion. |
| Fixed arguments | Status arguments compile as arrays and are passed directly to `spawn`; the flow CLI accepts exactly one flow positional, so caller argv is not broadcast. Zim2 retained `--activation-only`. |
| Mutation folding | A contained probe confirmed install exit `2` returned `2` and prevented the following invocation. Source maps other nonzero mutation exits to `1`. |
| Status folding | A contained probe confirmed `exit2: error` contributes final `1` while later reporters continue; existing tests cover drift and not-applicable. |
| Site selection | Closed catalog membership, duplicate IDs, placement-only semantic equality, cross-flow ownership, tombstones, and stale compiled-file exclusion are enforced before execution through shared `loadFlow`. |
| Bypass/duplicate triggering | Catalog execution is manual; the opt-in flag does not auto-run it. Existing Ansible `BINS_RUN_BYPASS` behavior remains separate, and runtime aliases have no `run`/action metadata. Leaf wrappers still evaluate their own host-runtime bypass guards when reached. |
| Alias timing | Catalog/runtime aliases are appended after `gen_bins`, so they cannot enter or recursively regenerate action compositors; filesystem materialization occurs later. |
| Build freshness | `pnpm build` reproduced the checked-in 138.21 kB (32.39 kB gzip) bundle without a diff; rendered scratch runtime hashes matched the checked-in artifact. |

## Verification performed

All completed checks passed unless the finding probes intentionally
demonstrated a defect.

- `pnpm check`
- `pnpm build` (no generated diff)
- syntax checks for `zim2.opt.pb` and `mise2.opt.pb`
- filter/compiler suites: runtime catalog, runtime bundles, bin compositors,
  CONFIG compile/context compile, Zim context compile, artifact LINKS
- runtime/flow suites: runtime catalog, catalog flow, orchestrator identity,
  structured status arguments, Node CLI arguments
- CONFIG integrations: command, contexts, consumer toolkit, graph, remote, and
  transaction faults
- Zim/Mise integrations: consumer lifecycle, remote promotion, demo-wrapper
  isolation, and Mise block status
- LINKS integrations: generation, status, systemd representations, and runtime
  manager tests
- existing `.test-agent/catalog-flow/{zim2,mise2}` catalogs, rendered wrappers,
  logs, aliases, flow dry-runs, and runtime hashes
- additional contained probes under `/home/rektide/tmp-opencode`: mutation exit
  `2` short-circuit, status `exit2: error` continuation, symlink escape, lexical
  comparator divergence, ambient foreign `DIR`, and runner-only `SIGTERM`

## Recommended gate

Do not run Zim2 or Mise2 catalog mutation flows live yet. Correct the two
deployment-containment defects and process interruption first, specify lexical
ordering, then extend the integration fixture across the omitted boundaries.
After that, rerender with redirected HOME/XDG/cache/settings targets and execute
the actual generated wrappers in the contained environment. The opt-in/default
boundary and authored-root compiler change can remain as implemented while
those corrections are made.

## Cross-references

- [`execution-model0.gpt6.md`](/design/config-anneal/execution-model0.gpt6.md)
  defines one invocation per file, observable lexical order, site placement and
  tombstones, fixed input, catalog authority, and the deferred mutation gate.
- [`effect-design0.glm53.md`](/design/config-anneal/effect-design0.glm53.md)
  independently identifies signal forwarding and detached process handling as
  required process-runner behavior; the requirement applies to this plain-Node
  executor as well.
- [`doc/bins.md`](/doc/bins.md) documents the legacy compositor hierarchy,
  caller-argument broadcast, and structured status protocol whose fidelity is
  under review.
- [`doc/config/log.md`](/doc/config/log.md#experimental-catalog-flow-authority)
  records the implementation's claimed validation surface; this review narrows
  the scratch evidence to render and dry-run confidence.

# Closure addendum — 2026-09-14

## Recheck scope and result

This addendum reviews the original implementation through `08de0fd1` plus the
containment/process correction `69b8fa08` and experimental isolation correction
`94fa4aaa`. It supersedes the original gate above where explicitly stated.

Five of the six original findings are substantively closed. The sixth,
execution evidence, is improved but remains open because the containment fix
introduced an untested, release-blocking multicall-alias regression. Catalog
mutation should therefore remain gated.

| Original finding | Status | Recheck evidence |
|---|---|---|
| Foreign ambient `DIR` | **Closed** | Every child receives `env: {...process.env, DIR: deploymentDir}` at [`files/flow/runtime.ts:89-95`](/files/flow/runtime.ts#L89-L95). The integration fixture starts the runner with `/foreign/deployment` and observes the selected deployment in both mutation and status children ([`catalog_flow.test.py:23-31`](/tests/integration/catalog_flow.test.py#L23-L31), [`catalog_flow.test.py:112-129`](/tests/integration/catalog_flow.test.py#L112-L129)). |
| Symlink executable escape | **Closed, with blocker below** | Both deployment root and configured executable are resolved with `realpath`, then compared for containment at [`files/flow/runtime.ts:72-86`](/files/flow/runtime.ts#L72-L86). The integration test's in-tree symlink to `/bin/true` is refused ([`catalog_flow.test.py:131-141`](/tests/integration/catalog_flow.test.py#L131-L141)). Absolute external targets follow the same realpath containment check. |
| Orphaned child after signal | **Closed** | Children run in detached process groups; `SIGINT`/`SIGTERM` are forwarded to the negative group PID; listeners are removed only on child error/exit; interruption folds to failure ([`files/flow/runtime.ts:89-123`](/files/flow/runtime.ts#L89-L123)). The test waits for a mutating child, terminates the parent, observes the child's trap, and requires nonzero parent completion ([`catalog_flow.test.py:150-203`](/tests/integration/catalog_flow.test.py#L150-L203)). |
| Locale-dependent ordering | **Closed in implementation** | Both layer reads and final selection use the explicit code-unit comparator at [`files/catalog/runtime.ts:90-92`](/files/catalog/runtime.ts#L90-L92), [`files/catalog/runtime.ts:193-196`](/files/catalog/runtime.ts#L193-L196), and [`files/catalog/runtime.ts:307-309`](/files/catalog/runtime.ts#L307-L309). A punctuation/case regression assertion would still strengthen this closure. |
| Zim2/Mise2 live-target isolation | **Closed for declared effects** | Zim2 now has distinct CONFIG selectors/subpath, loader root, caches, and registry ([`zim2.opt.pb:8-12`](/zim2.opt.pb#L8-L12), [`zim2.opt.pb:41-73`](/zim2.opt.pb#L41-L73)). Mise2 now targets separate Bash files, ZDOTDIR, and `MISE_CONFIG_DIR` ([`mise2.opt.pb:35-50`](/mise2.opt.pb#L35-L50), [`mise2.opt.pb:54-77`](/mise2.opt.pb#L54-L77)). Rendered specs/env files contain those isolated destinations. `files/zim2 -> files/zim` remains intentional implementation-source sharing, not shared deployed state. |
| Adequacy of execution evidence | **Open** | Foreign `DIR`, external symlink rejection, process-group interruption, success ordering, status drift/not-applicable continuation, authority refusal, and rendered isolation are now covered. Multicall aliases are not, and the fixture still has no committed mutation-failure short-circuit, `exit2: error`, code-unit punctuation/case, site-selected execution, or runtime execution of an authored root plus child. |

## New high-severity blocker — realpath validation destroys multicall alias identity

`executablePath()` correctly resolves the configured path for containment, but
returns the resolved target at [`files/flow/runtime.ts:80-86`](/files/flow/runtime.ts#L80-L86).
`runInvocation()` then spawns that target at
[`files/flow/runtime.ts:136-141`](/files/flow/runtime.ts#L136-L141). For a safe
symlink that is intentionally an argv-zero interface, this changes observable
behavior rather than merely validating it.

The rendered Zim2 status flow demonstrates the regression:

```text
descriptor handler: bin/config-status.sh
real target:         bin/compfuzor-runtime.mjs
dry-run reports:     bin/compfuzor-runtime.mjs
```

Invoking `config-status.sh --help` directly selects CONFIG and succeeds.
Invoking its resolved `compfuzor-runtime.mjs` target without a domain argument
returns the omnibus usage error. This follows directly from the dispatcher's
intentional lexical symlink-chain classification
([`files/runtime/compfuzor-runtime.ts:41-85`](/files/runtime/compfuzor-runtime.ts#L41-L85)).
An actual contained Zim2 status-flow probe reached the resolved omnibus path for
the `config-status.sh` entry rather than the alias. Depending on PATH it either
fails before Node in the local Mise shim or reaches the omnibus usage failure;
in neither case does it execute CONFIG status.

Containment and invocation identity need separate paths: validate the real
target against the real deployment root, but spawn the contained lexical alias
(or otherwise preserve the configured argv-zero contract). Add a flow test with
a contained alias to the omnibus runtime; an external-target alias must still
fail. This is a blocker for CONFIG flow entries and any other runtime alias used
as a catalog handler.

## Authored aggregate fidelity recheck

The `08de0fd1` behavior remains correct. A generated legacy root with any
non-empty authored body field is represented as one opaque root invocation;
its `run_all` executes inside that root, so body ordering, local bypass handling,
and child short-circuit semantics remain shell-owned. The rendered Mise2 catalog
still has exactly one install entry targeting `bin/install-user.sh`; the
rendered root contains both its Mise-settings body and one
`install-bash-user.sh` child. No child is separately scheduled, so there is no
duplicate execution or recursion.

## Recheck verification

The following passed on the post-`94fa4aaa` tree:

- `pnpm check` and `pnpm build`; the build reproduced the checked-in 139.14 kB
  (32.67 kB gzip) runtime without a build-artifact diff.
- `zim2.opt.pb` and `mise2.opt.pb` syntax checks.
- Runtime catalog, catalog flow, orchestrator identity, structured status args,
  and Node argument integrations.
- Runtime catalog/bundle, bin compositor, CONFIG compiler/context, Zim context,
  and artifact LINKS filter suites.
- CONFIG command, contexts, consumer toolkit, graph, remote, and transaction
  fault integrations.
- Zim consumer, remote, and wrapper integrations; Mise block integration.
- LINKS generation/status and systemd LINKS integrations.
- Post-fix contained Zim2/Mise2 render inspection and install/status dry-runs.
  Zim2 declares two install and three status entries with isolated Zim paths;
  Mise2 declares one opaque install root and one status entry with isolated Mise
  paths. Both rendered runtime hashes match the checked-in bundle.

The existing flow integration itself passes, but the contained alias probe
above fails semantically and is the release gate. No implementation was changed
during this recheck.

## Updated gate

The original `DIR`, escape, signal, ordering, and experimental-target findings
no longer block execution. Preserve those corrections. Do not promote catalog
flows to live mutation until contained aliases retain argv-zero identity and a
regression test proves both halves of the rule: safe internal aliases execute
as aliases, while aliases resolving outside the deployment remain refused.
