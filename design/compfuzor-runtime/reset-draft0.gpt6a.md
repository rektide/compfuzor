---
type: ArchitectureProposal
title: CFR reset — native composition, bound domains, shared implementation
description: A coherent proposed runtime with native Effect authoring, explicit invocation and admission, selected environment views, domain-owned transactions, terminating bootstrap, and a deletion-oriented landing sequence.
resource: /design/compfuzor-runtime/reset-draft0.gpt6a.md
status: draft
generated: {by: 'model:openai/gpt-6-astra#medium', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed178679dffeCgFbocaRLfqrm2
    title: sunny-moon — new integrated reset design grounded in current source and installed Effect rc.118
  - resource: opencode://ses_ed3f4aaaaffePYlWeomteOWlbg
    title: brave-meadow — architectural commission and recent human constraints
  - resource: /design/compfuzor-runtime/reset-assessment0.gpt6a.md
    title: Companion assessment, option comparison, inspected source inventory, and verification limits
  - resource: /design/compfuzor-runtime/composition-problem0.gpt6a.md
    title: Original architectural ambition and design tests
  - resource: /design/compfuzor-runtime/experiments0.gpt6a.md
    title: Retained evidence and explicit limits after four closed experiments
  - resource: /design/compfuzor-runtime/effect-draft2.gpt6a.md
    title: Predecessor native contributions, shared init, mutable collaboration, and history
  - resource: /doc/config/definitions.md
    title: Actual independent CONFIG and ENV contracts
  - resource: /doc/config/simplification.md
    title: Preserved product contracts and deletion test
  - resource: /doc/actions/README.md
    title: Actual admission, audience, and shell-body compatibility requirements
  - resource: /runtime/registry/README.md
    title: Existing receiver rendezvous and accepted-membership boundary
  - resource: /design/runtime-sourcing/direction0-syn.gpt61sol.md
    title: Editable provider-selection preference and SHA-512 burn direction
  - resource: /design/compfuzor-runtime/environment0.gpt6a.md
    title: Selected defaults and new-CFR human direction
  - resource: /design/compfuzor-runtime/environment1.gpt61sol.md
    title: Reported selected-view and live-shell receipt findings, narrowed adoption contract
  - resource: /design/fuzings/proxy0.gpt61sol.md
    title: Concrete proxy/native Zim integration and explicit source-order prerequisites
  - resource: /design/confext/build-inputs1.fx.md
    title: Corrected confext material, mode, destination and artifact-format research
  - resource: /files/config/runtime.ts
    title: Existing CONFIG admission and complete execution functions
  - resource: /files/config/assembly.ts
    title: Existing sole transaction-worker invocation and root coupling
  - resource: /files/config-run.sh
    title: Spec-bound deployment, processor leaves, and candidate transaction
  - resource: /files/actions/operations.ts
    title: Current typed-operation adapter and domain-switch replacement seam
  - resource: /files/config-remote/runtime.ts
    title: Existing independent target fanout and rollback contract
  - resource: /files/config-env.py
    title: Literal parser/reducer to reuse
  - resource: /node_modules/effect/src/workflow/Activity.ts
    title: Installed native Activity construction and retry semantics
  - resource: /node_modules/effect/src/workflow/Workflow.ts
    title: Installed Workflow construction, execution identity and handler registration
  - resource: /node_modules/effect/src/workflow/WorkflowEngine.ts
    title: Installed memory-engine caching, registration context, and execution lifetime
verification:
  scope: Design grounded in source inspection and attributed earlier evidence
  result: Proposed CFR interfaces and examples are not implemented or typechecked; no runtime or live effects performed
---

# 1. Decision and destination

**CFR is the common place to discover, bind and compose work; domains remain the
owners of what that work means and when it commits.** Effect is the execution
foundation. Native TypeScript modules export annotated Workflows and Activities.
The CLI, imported library use, generated compatibility entries and Ansible-triggered
calls all select the same contributed work.

This is a new proposal, not an accepted spec or an implementation claim. The
[assessment](reset-assessment0.gpt6a.md) compares alternatives and records the
source evidence. The destination retains the original high ambition: open
contribution, broad/narrow navigation, reusable programs, shared initialization,
mutable collaboration, durable history, material/exposure understanding, build-only
confext, and a host runtime usable before a deployment exists.

The first landing is deliberately smaller: selected environment inspection and
explicit proxy refresh, followed by an integrated native/legacy composition
replacement. It does not require general resume, fuze enrollment, or a global
material database.

## Terms and ownership

| Term | Meaning |
|---|---|
| Definition | Native Workflow tag or Activity name, qualified by its admitted module provenance. |
| Membership | A named declaration placing a definition/binding into a public collection; several memberships can refer to one definition. |
| Occurrence | One intended call in one run, including target and role. Two calls are two occurrences unless explicitly addressing the same existing occurrence. |
| Deployment | The workload/data being operated on; identified independently of the executing code. |
| Provider | One selected compatible implementation closure: code, shared workers, assets and dependencies. |
| Admission | Domain validation and binding of an operation's receiver, arguments, resources and selection before its body effects. It need not require outputs that the body will create. |
| Workspace | Run-local typed mutable collaboration, with immutable observations/bindings retained alongside it. |
| Receiver | A domain-advertised destination, distinct from both a deployment and its implementation provider. |
| Material / exposure | Owned bytes and their location / a link, copy or other declared presentation of those bytes elsewhere. |

```text
entry + explicit deployment + request
  → select implementation provider
  → discover native contributions + generated compatibility contributions
  → shared init: observe → adjust → resolve
  → select collection / admit domain operations
  → native Effect composition
       ├─ complete CONFIG / Zim / keybinding operations
       ├─ opaque rendered bins
       ├─ selected environment decisions and shell bridge
       └─ material consumers such as confext
  → outcomes and durable invocation history
```

CFR owns the relationships at these boundaries, not a second merger, installer,
transaction engine, process scheduler, or universal provisioning graph.

# 2. Native authoring and execution identity

## Public module form

Keep draft2's native export direction. No mandatory `defineModule` envelope, no
registration side effect during import, and no compulsory CFR program AST.

- A recognized typed annotation marks a public native Activity or Workflow.
- Its native identity and result schemas remain authoritative.
- Annotation data supplies description, tags, public routes/memberships, supported
  audiences, contract version and any declared outline.
- A separate lazy binding annotation supplies a Workflow's handler Layer and
  advertised service/interface requirements. Inspection does not acquire the Layer.
- An Activity input binding names a Schema and the request service its body reads.
  The input schema is a CFR boundary addition, not an upstream Activity property.
- An explicit inert membership export can join an existing definition elsewhere.
  This avoids modifying a provider merely to compose it in a second consumer.

All `Cfr.*` names below are proposed contracts. `Workflow.make`, `Activity.make`,
`annotate`, `toLayer`, `Effect.gen`, and Context services are verified rc.118 shapes.
Domain services and schemas are illustrative imports, not currently exported APIs.

```ts
// runtime/proxy/client.ts — native, import-safe authored module
import { Effect, Schema } from "effect";
import { Activity, Workflow } from "effect/workflow";
import * as Cfr from "@compfuzor/cfr-sdk";
import { EnvironmentRequest, EnvironmentSelection, EnvironmentViews, Snapshot } from "./environment.ts";
import { ConfigOperations, AssembleInput, ConfigFailure } from "../config/service.ts";

export const defaults = Activity.make({
  name: "proxy.client.defaults",
  success: Snapshot,
  error: ConfigFailure,
  execute: Effect.gen(function* () {
    const request = yield* EnvironmentRequest;
    const views = yield* EnvironmentViews;
    return yield* views.read(request);
  }),
  interruptRetryPolicy: Cfr.noAutomaticRetry,
}).annotate(Cfr.Contribution, {
  version: 1,
  description: "Read selected client literals and their winning sources",
  tags: ["proxy", "environment"],
  route: ["defaults", "proxy", "client"],
}).annotate(Cfr.ActivityInput, Cfr.input({
  service: EnvironmentRequest, schema: EnvironmentSelection,
}));

export const assemble = Workflow.make("config.assemble", {
  payload: {
    runId: Schema.String,
    occurrence: Schema.String,
    input: AssembleInput,
  },
  idempotencyKey: ({ runId, occurrence }) => JSON.stringify([runId, occurrence]),
  error: ConfigFailure,
}).annotate(Cfr.Contribution, {
  version: 1,
  description: "Complete assembly of one bound CONFIG selection",
  tags: ["config"],
}).annotate(Cfr.Handler, () => AssembleLive);

const AssembleLive = assemble.toLayer(({ input }) => Effect.gen(function* () {
  const config = yield* ConfigOperations;
  const admitted = yield* config.admit(input);
  yield* config.execute(admitted);
}));

Cfr.runIfMain(import.meta.url, () => import("./client.main.ts"));
```

The shared config implementation belongs in its own domain module in actual code;
the two exports above show the two native forms together, not a requirement to
redeclare `config.assemble` in every proxy. Generated complete CONFIG bindings join
that one definition with distinct `(deployment, definition, context, recipe)` inputs.
The exact binding schema is validated at admission; no global domain-kind union is
needed. Native handler Layers resolve typed services at the run boundary.

`runIfMain` asynchronously realpaths the invoked file and module, then dynamically
loads the CLI using a handled continuation. Direct execution and central execution
enter the same common runner. Import never starts init or performs provisioning.
Ordinary exports are ignored; malformed advertised exports fail visibly.

## Occurrence semantics without Activity renaming

Every fresh managed run receives a new run ID. An occurrence is named within it,
for example `build/opencode/status-before` and `build/opencode/status-after`.
Identical definition, arguments and target do **not** collapse these calls.

For public Activities, the admission layer creates/registers one small native
Workflow definition per admitted Activity definition. Its payload carries run ID,
occurrence and decoded input; its handler supplies that input service and yields
the original Activity once. Distinct Workflow execution IDs give distinct Activity
cache keys. Register the handler once in the run's scoped engine, not once per call
with different captured input. This avoids the nonexistent public rename API and
avoids double-wrapping `activity.execute`'s interruption retry logic.

Native public Workflows use the same run/occurrence envelope in their payload
contract. A foreign Workflow with a business idempotency key requires an explicit
adapter; do not silently overwrite its semantics. Private Activities inside a
domain Workflow can use normal upstream semantics, but repeated observations need
separate names or public occurrence calls. CFR cannot statically police arbitrary
generator code.

The managed invocation helper rejects reusing one occurrence ID with different
definition/input/target. An explicit query of an already recorded occurrence reads
history; a fresh `run status/...` performs a new observation.

The first execution profile is finite, sequential work with no durable suspension
or automatic mutation retry. Long-running servers and suspending workflows advertise
a different unsupported profile initially. Source inspection establishes upstream
mechanisms, not integration correctness: child identity, captured Layers, interrupt
outcome preservation and unexpected-suspension handling are required conformance
checks at the integrated landing.

# 3. Contribution collection, navigation, and truthful inspection

## Routes select declared work

Public paths are arrays of segments. `apply/network/extra-addr` narrows the
`apply/network` selection within the same deployment, audience and collection
semantics. Hyphens are characters, not recursive separators. A prefix does not
mean “execute every similarly named export.”

Each public collection owns an explicit membership domain and broad-run behavior.
A leaf route points at one membership or complete domain workflow. A parent route
collects its declared subtree. A directory that has no broad operation is browsable
but `run` reports that it is not runnable; empty or unknown selection is not success.
Related-operation links such as `verifies` are discoverable, not automatic calls.
`apply-and-check/network` can explicitly call apply then status.

```ts
// Proposed inert bridge declarations, associated with existing definitions.
export const clientConfig = Cfr.membership({
  id: "proxy.env.assemble",
  definition: assemble,
  collection: "build",
  path: ["proxy", "environment"],
  stage: "prepare",
  input: { definition: "env", context: "canonical" },
});
// Target deployment is supplied by the invocation, not this code's realpath.
```

Collection is semi-recursive: a member may be a complete workflow or a collector
of another declared collection. Track the active collection/membership path and
reject cycles. Collapse duplicate discovery of the **same membership ID** within
one collection snapshot; different IDs remain distinct calls even when their
definition/input coincide. Re-exports of the same native value consolidate source
provenance. Distinct definitions claiming the same qualified identity fail.

## Order is local to the parent program

Sequential execution is the default. Within one collected stage, honor explicit
`before`/`after` membership edges and declaration order for unconstrained members.
Reject required missing edges and cycles. Stable enumeration is a tie-break, not
a prerequisite inference. An optional edge must be marked optional explicitly.

- A **complete-pipeline collector** runs A's whole pipeline, then B's whole pipeline.
- A **staged parent** explicitly collects all assembly work, then publication work.
- A complete domain transaction is opaque to the parent's scheduler and cannot be
  split across barriers. A domain may separately export genuinely separable steps.
- Legacy BINS preserves its existing lane sort and contiguous subsystem grouping;
  earliest-member placement is labeled compatibility order, not a global barrier.
- Narrowing retains these semantics; it does not secretly ignore phases or broaden
  an audience. Required external prerequisites either run as explicit prerequisites
  of the selected operation or block it; they are not silently guessed from IDs.

No universal `config = assemble → publish` sequence: ordinary assemble-mode CONFIG
already commits its consumer output. Zim's normal installer owns its full channel,
cache and loader sequence. Systemd scope is not a CONFIG context.

## Three inspectable products

| Product | What it promises |
|---|---|
| Catalog | Definitions, memberships, routes, source provenance, advertised interfaces and optional outlines. No bodies or handler Layers executed. |
| Plan | Exact currently resolved collection and admitted bindings; unknown future discovery/branching marked dynamic, script internals marked opaque. |
| Trace/history | Actual managed calls, attempts, outcomes and selection/revision facts. No fabricated script-internal commands. |

The collection resolver returns a schema-backed immutable selection; both `plan`
and execution consume that same structure. It contains IDs, bound target, ordered
membership occurrences, reasons/omissions and code/source observations. This is a
collection result, not an authored replacement workflow language.

For arbitrary `Effect.gen`, an optional outline is documentation, labeled
**declared outline**, never an exact plan. Do not walk a generator with invented
results. Domain `check` can execute validators or processors and is a separately
requested operation, not hidden inside catalog/plan.

## CLI and library surface

Proposed common frontend, implemented through `effect/cli`:

```sh
cfr --deployment /srv/proxy list build
cfr --deployment /srv/proxy explain build/proxy/environment --json
cfr --deployment /srv/proxy plan build --audience user --json
cfr --deployment /srv/proxy run build/proxy/environment --audience user
cfr --deployment /srv/proxy query memberships --definition config.assemble --json
cfr --deployment /srv/proxy defaults proxy/client --definition env --recipe proxy-client.env
cfr --deployment /srv/proxy provider explain --json
cfr history show RUN_ID --json
```

`--audience` belongs to the new interface; existing audience aliases retain their
asserted audience and cannot be overridden across scopes. Bare audience selection
uses the deployment's declared default, ordinarily user; no user→system fallback.
Domain options decode at their own admission boundary. Broad mixed-domain runs
reject options not accepted by every selected binding rather than scrub arguments.

```ts
// Proposed library calls: Effects, usable within another native workflow.
const catalog = yield* Cfr.discover({ deployment, provider });
const selected = yield* Cfr.select(catalog, {
  path: ["build", "proxy", "environment"], audience: "user",
});
const result = yield* Cfr.run(selected, { request });
```

Typed callers may invoke an imported definition without string lookup through
`Cfr.invoke(definition, input, { occurrence })`. Both paths use common admission,
policy, history and workspace services. Scripts receive versioned JSON through
query/list/plan and invoke explicit paths; they do not source runtime internals.

# 4. Shared init, admission frontiers, and mutable collaboration

## Initialization

Minimal bootstrap binds entry, provider, deployment, fresh run ID, initial roots,
process/filesystem services and history location. It cannot depend on application
ENV or a module under a deployment that does not exist yet.

Most workflows use:

```text
discover → init/observe → init/adjust → init/resolve → requested work
```

Init is extensible through ordinary declared memberships. It observes specs and
selected environment inputs; local contributors can modify typed settings and
candidates; the consuming domain validates effective values. Defaults and original
observations remain available. Nested work joins the existing workspace, not an
accidental second init; explicit reload is a new occurrence. Bootstrap operations
use a reduced profile and do not recursively initialize themselves.

## Admission before effects, without pretending the whole future is known

For a known aggregate, resolve/admit **all known selected domain bindings before
its first authored body**. Preserve current audience-action guarantees. Inputs and
outputs the body will create need not already exist merely to bind a destination.
At execution, domain validation still checks actual candidates and native conditions.

Dynamic discovery opens a later explicit admission frontier. Its new work cannot
enter an earlier frozen batch or redirect a prepared operation. The plan names that
boundary; no whole-run “all effects were preflighted” claim is made. A late invalid
binding can fail after earlier independent work committed.

Provider choice, deployment identity and admitted receiver paths are immutable.
Mutable collaboration affects unadmitted future operations, not their already
selected predecessors. This is how draft2's normal mutation coexists with today's
tested pre-effects admission.

## RunData contract

Use a scoped `Context.Service` for a typed, schema-validated workspace. Field keys
include stable domain/version and relevant complete target coordinates:

```text
EnvironmentSnapshot(deployment, definition, recipe, context)  immutable observation
EnvironmentIntent(binding)                                 mutable pin/reset intent
ConfigSettings(deployment, definition, context)              mutable settings
ConfigResult(deployment, definition, occurrence)             completed result
```

`read`, `set`, `update`, and explicit removal operate on protected snapshots.
Updates have writer occurrence and increasing revision; no invisible shared-object
mutation. Values can intentionally replace earlier contributions. Begin with serial
writers; parallel updates require atomic/revision-checked service operations and
explicit domain conflict rules. Read dependencies do not invent a scheduler.

For normal native code, mutate outside cacheable Activity bodies:

```ts
const snapshot = yield* Cfr.invoke(defaults, selection, { occurrence: "observe-client" });
yield* workspace.set(snapshotField(selection), snapshot, { transition: "load-client" });
const intent = yield* workspace.read(intentField(selection));
const decision = resolveProxy(snapshot, observedShell, receipt, intent);
yield* workspace.set(decisionField(selection), decision, { transition: "resolve-client" });
```

Here `resolveProxy` is pure domain composition over the shared environment resolver.
The original snapshot is not overwritten with its effective values.

**Replay contract:** cached results must re-enter the same explicit transitions
against state reconstructed at the matching workflow position. Record stable
transition identity, input revision and validated after-values/results. A retained
workspace must detect already-applied transitions; a reconstructed workspace must
apply them in order. General update closures are not persistence data. No hidden
stateful-Activity write-capture helper is in the first implementation.

Initial managed execution does not advertise cross-process replay or suspension.
The future resume profile requires proving position-matched reconstruction, pinned
code/dependencies, reproducible selection, and domain recovery after unknown host
effects. Merely saving this workspace or a successful Activity result proves none
of those. Domain transactions and shell receipts are not replaced by the run journal.

# 5. Discovery, implementation sourcing, and terminating bootstrap

## Three selections, kept distinct

1. **Provider resolution:** choose one compatible implementation closure.
2. **Contribution discovery:** collect many native/generated workload declarations.
3. **Receiver rendezvous:** ask a domain's registry which receivers participate.

The host executable's realpath identifies its provider, never the deployment being
operated on. Global `cfr` requires `--deployment` or an explicit deployment-bound
entry. A bound local entry retains lexical action/audience identity and a physical
deployment locator before following provider indirection. Ambient `DIR` and cwd
do not choose the target.

## Provider policy

Deploy editable `etc/cfr/provider.json` with a version, source locators, supported
ABI/interface requirements, SHA-512 burn reference and ordered stages:

```text
changed(rendering-source locator, deployment burn)
→ canonical(explicit locator or host provider registration)
→ deployed(optional packaged closure)
```

The source of `changed` and the canonical default remain operator choices. Recommend
recording the rendering checkout explicitly and using a host registration for
canonical, with a configured checkout path as a normal locator. Do not silently
hard-code an archive path from one author's home.

Each candidate must supply the required **whole** code/tool/asset closure and ABI.
Absent, unchanged or incompatible candidates report their reason and fall through
before execution; malformed policy/burn fails as configuration error. If `changed`
is enabled but its baseline is missing, do not pretend it is unchanged. A selected
provider that fails during loading or operation execution does not trigger retry
through another provider.

Define a conservative provider-owned source-set manifest: domain source directories,
shared runtime/SDK code, worker assets, package metadata and lockfile, including
set membership. Hash sorted relative paths and bytes with SHA-512 at deployment.
This deliberately hashes some unused code rather than pretend one entry-file digest
captures transitive imports. Exclude documentation by explicit source-set ownership.
An unaccounted dynamic dependency makes a provider incomplete for changed-selection;
it is not silently omitted. Burns are selection baselines, not signatures or resume
archives; invoking a command does not refresh them.

Resolution is frozen per invocation. Mutable source mode records observations and
cannot claim immutable code under concurrent edits. A packaged content-identified
closure is the reproducible mode. Later discovery can add workload modules compatible
with the selected ABI; it cannot replace already admitted implementation bindings.

## Native module discovery and dependency delivery

Default workload root: `<deployment>/runtime/`, domain-grouped. Provider built-ins
are discovered separately and contribute implementations, not another deployment's
workload. Generated legacy/CONFIG binding data remains under `etc/cfr/`; derive it
from existing native declarations, not another hand-maintained input list.

Scan `.ts` and `.mjs` modules recursively, excluding `.d.ts`, dependency/VCS trees
and hidden paths by stated policy. Ignore ambient `.gitignore`. Follow a module
symlink only within explicitly enrolled source roots; additional roots are an
explicit discovery request. Canonical module identity prevents duplicate imports;
distinct duplicate definitions fail rather than last-file-win. A helper-only module
is inert for registration, but still must be import-safe. Trusted JS imports can
execute top-level code; data-only inventory uses a catalog snapshot with its source
identity and staleness shown.

**Delivery recommendation:** a versioned host ABI package slot provides
`@compfuzor/cfr-sdk` (built JavaScript plus types) and the pinned compatible
Effect/platform packages. Native
contribution packages use ordinary Node package resolution through installed
dependencies/package links to that slot; do not mutate a shared `node_modules`
link each time a provider is selected. Provider candidates in one ABI family use
the same pinned contract packages. A deployment runtime package's dependency
arrangement is installed during explicit preparation, with incompatible requests
rejected rather than blended. Extra dependencies belong to that package's closure.

New CFR source execution requires Node >=24.11 and the supported erasable TypeScript
subset. Compiled `.mjs` modules are also valid. Author `.ts` imports normally; use
the existing central build tooling for packaged delivery. This is a deliberate
stronger prerequisite for new CFR, not a retroactive requirement on old bins.
No custom loader or assumption that global npm installation resolves arbitrary
deployment imports. The first integrated checkpoint must run outside the checkout
to establish this arrangement, including one contributed module dependency.

## Practical bootstrap

```sh
# Node + a usable provider checkout/package are prerequisites.
node /path/to/compfuzor/runtime/cfr/cli.ts runtime expose --prefix "$HOME/.local"
# The exposed host command can now operate on unrelated material.
cfr --deployment /srv/example provider explain
```

Names/layout above are proposed. The locally invoked `runtime expose` uses a
bootstrap profile, its explicit current provider and the ordinary LINKS delivery
primitive. It does not search for global cfr or read application ENV. An Ansible
bootstrap playbook ensures Node/package prerequisites and calls this same operation.
A minimal bound launcher can resolve editable provider policy using only Node
builtins before loading Effect; that locator is a small versioned bootstrap
protocol, not another provisioning engine.

Missing global exposure is recoverable by the explicit local command. Missing all
configured providers fails before work, with the examined locators and installation
route. Optional packaged fallback is declared; absence does not revive old shell
aggregation. Ordinary rendering can emit data/entries without running CFR; a play
that requests runtime work must satisfy bootstrap first.

Pre-write preparation receives root/storage intent from outside the uncreated
deployment. It runs before repository checkout or filesystem materialization.
Directory and eventual btrfs preparation are domain implementations; existing
non-subvolume directories require deliberate migration. The earlier scratch marker
probe is not a btrfs implementation. Confext packaging is unrelated to this ordering.

## Worker closure and version boundaries

The retained CONFIG adapter must evolve from `runner: path` to explicit
`{deploymentRoot, spec, workerResources, environment}`. Shared worker resources
include runner, processors, ENV reducer and required callbacks. Per-definition
recipe leaves, user processors and validation commands remain workload data.
No worker/resource lookup derives the deployment from the provider's directory.

Old generated recipe leaves that refer to deployment-local processors remain an
explicit legacy packaged closure until regenerated. A new shared worker profile
passes explicit resources into its leaves and removes those local assumptions.
Selecting a newer JS entry must not silently combine it with incompatible old
worker assets. Initially an opaque old-domain executable is a declared dependency
of an adapter, not falsely advertised as a fully shared-worker migration.

Version independently: launcher protocol, native SDK/Effect ABI, contribution
annotation schema, domain spec/worker interface and history schema. Refuse unsupported
major/interfaces before domain effects. A runtime version floor alone cannot
establish worker compatibility. Defaults remain editable data; history records the
actual selected versions, not merely the configured range.

# 6. Worked CONFIG → ENV → proxy path

Assume deployment P has independent complete definitions `env` and `application`;
the normal Zim host Z owns its own complete `zim` definition and activation adapter.
These share implementation, not recipe namespaces or transaction scope.

1. P's existing authoring produces `50-proxy-service.env`, `60-proxy-client.env`,
   and `99-local-priority.env`. Service projection selects 50+99; client projection
   selects only 60. No second env-selection manifest is authored for CFR.
2. `build/proxy/environment` invokes the existing ENV CONFIG assembly transaction
   before an admitted Rust build that needs its output. Its bootstrap profile does
   not first source the very output being assembled.
3. Normal Zim producer import explicitly assembles P's ENV before linking/copying
   its native module into Z's existing inputs and building Z's caches. This remains
   normal ZIM work, with explicit root/membership links. No fuzing descriptor is
   necessary. Import is another transaction; it does not undo successful producer
   assembly if host import later fails.
4. The native selected-view operation binds `(P, env, proxy-client.env, canonical)`
   using the generated spec's actual recipe identity. It reads ordered exact inputs
   through the existing literal reducer and returns source digests, normalized
   source values, reduced defaults and winner indexes. It never evaluates exports.
5. The proxy domain resolves URL first, then derives native shell-word-safe args
   from the effective URL. It does not move native CLI explicit `--server`/
   `--standalone` precedence or shared port authority into CFR.
6. A selected child process receives an explicit environment projection. Host
   inheritance is a separate flag/policy; selecting the client does not erase an
   inherited service credential. Execution root is bound independently of any
   application key named `DIR`.
7. Explicit live-shell refresh asks the caller's Zsh bridge for selected presence/
   values, including unexported scalars, and its nonexported local receipt. The pure
   resolver returns changes/reasons and a proposed receipt. The shell checks stale
   observations and assignability, applies, verifies and acknowledges. Only that
   acknowledgment advances the same shell's baseline.

This source-aware observation is not proof that an already generated export is
currently published or validated. The initial apply profile accepts exact literal
recipes without custom validation hooks; unsupported recipes fail explicitly.
Multiple file reads are observed inputs, not a filesystem-atomic snapshot.

## Retained-default decisions

Adopt the [probe's proposed policy](environment1.gpt61sol.md#3-minimum-change-knowledge)
as the recommendation for review:

| State | On explicit refresh |
|---|---|
| Managed; current equals last applied | Follow the new selected candidate. |
| Managed; current differs, including empty/absent | Preserve and mark held/detected-edit. |
| Held | Preserve until explicit reset, even if equal to today's default. |
| Untracked present | Preserve and record held/untracked after successful apply. |
| Untracked absent | Bootstrap a candidate if present. |
| Literal default removed | Retain prior value/basis and report removal; no automatic unset. |

Generic empty means present. Proxy bootstrap alone preserves its existing
empty-or-unset-means-default behavior; subsequent managed changes to empty/absent
are local edits. For an intentionally absent/empty effective URL, recommend absent
derived args when args remain managed, retaining custom args. That explicit domain
refresh behavior needs operator confirmation before normal startup adoption.

If A was the managed URL and today's default becomes B, unchanged URL/args follow
B. A local URL C survives while still-managed args become args(C). Custom args
survive independently. Without receipt, equality with A does not establish ownership;
explicit reset is the migration operation. Pin records intentional preservation
even when values equal defaults. `defaults` remains readable while C is effective.

One live proxy receipt owns one binding. A foreign target/definition/recipe/domain
policy cannot take turns claiming the same shell variable. New shells do not inherit
that receipt. Child execution never acknowledges the parent. Failed/partial apply
retains the old receipt; this is conservative recovery, not signal-safe rollback.
Initial support is nonsecret ordinary proxy scalar state. General shell attributes,
multiple owners and credential persistence are outside this first domain profile.

**Adoption deletion:** once normal Zim startup uses this managed bridge, remove the
old competing default-writing path for that binding. Until then refresh is explicit;
re-sourcing the legacy module can still change values. Do not claim continuous
management while both writers remain independently active.

# 7. Other domains and the original architectural tests

## Repeated work and barriers

```ts
// Proposed native handler body; private normal Effect composition remains normal.
const before = yield* Cfr.invoke(status, input, { occurrence: "status-before" });
yield* Cfr.collect("build", { subtree: ["opencode"], occurrence: "build" });
const after = yield* Cfr.invoke(status, input, { occurrence: "status-after" });
return compare(before, after);
```

Both status calls execute. Build does not restart a service. An existing mixed
OpenCode authored root is initially one opaque occurrence, including its own
children; collecting its advertised descendants does not run them a second time.
After deliberate extraction, a native workflow can preserve its dependency build,
artifact merge, CORS-before-args order and complete child binding, and delete that
root's independent child loop.

For a multi-domain configure operation, choose either complete child pipelines or
explicit assembly/publication barriers in its native body. Do not split an installer
that both assembles and commits merely because it is a member of an “assembly” group.
Use a new precise stage export when a domain genuinely supports it.

## Remote fanout and keybindings

Expose `config-remote put-matching` as one complete domain batch initially. It admits
all selected destinations before delivery, then preserves per-target rollback and
continues later admitted targets after failure. Its result lists all outcomes;
CFR's ordinary fail-fast collection policy does not overwrite this domain policy.

Keybinding offer installation similarly uses existing registry selection, masks,
force-enable rules and captured guards. Accepted membership and native output
remain one consumer CONFIG commit. Advertisement can survive native rejection;
registration is not activation. Different receiver IDs may use the same adapter.
No generic program collector scans advertisements and calls them accepted inputs.

## Material/exposure and confext

Material is an optional domain projection available to more than one operation,
not a prerequisite for admitting a bin. A minimal material view records:

```text
identity; byte source and its base root; producer/owner provenance;
observed content/mode where inspected;
exposures: destination + base + copy/link policy + required mode;
external references and known relocation constraints
```

It can be produced from native declarations or existing rendered bytes plus LINKS
records. Link direction is explicit: project-owned bytes exposed outward differ
from system-owned bytes linked into a project. A single-tree layout relocates byte
ownership deliberately and retains those relationships. Absolute paths embedded in
content and live producer links remain relocation constraints, not magically portable
because the directory is contained.

`build/confext/iface` selects declared intended destinations under `/etc`, consumes
already-rendered bytes, checks collisions/symlinks/modes and stages an artifact.
It never invokes install/apply to infer material. For legacy input without receipts,
record “observed bytes and declared destination; production lineage unverified” rather
than reject admission. Packaging does not regenerate unless the user selects a
larger workflow that explicitly realizes material first.

First case: static-only's standalone `.network`; second: extra-addr's drop-in for an
explicit governing filename. LINKS mappings alone do not provide package mode policy.
Declare target files 0644/directories 0755 for these payloads rather than inherit the
historical rendered 0660 and rely on apply-time chmod. Keep that packaging policy
visible, not a change to all material modes.

Recommend directory output first, with explicit host compatibility metadata and
`etc/extension-release.d/extension-release.<artifact-name>`. EROFS and DDI remain
in-scope future output adapters, not activation. Record source hashes/destinations/
modes in a sidecar outside payload. Destination selection initially uses explicit
IDs and segment-prefix inclusion; a richer ordered include/exclude/reinclude grammar
must be specified and tested before claiming gitignore compatibility. No implicit
hidden-file rules or whole-DIR payload selection.

Realization, exposure and artifact status are independent: existing material can be
healthy and packageable with no host exposure. Build completion says nothing about
network reload or confext merge. This supplies the original material test without
holding ENV or BINS adoption hostage to a universal asset ledger.

# 8. History and execution policy

## Minimal meaningful durable history

Persist one schema-versioned append-only journal per fresh run in an explicit
state location (default invoking user's XDG state area; system invocations require
an explicitly writable policy, not implicit sudo). Record:

- request/run/parent and occurrence IDs; deployment and selected provider identity;
- module and membership selection provenance, admission outcome and input revision;
- public occurrence requested, actual attempt start, complete/fail/interruption or
  unknown outcome; domain outcome summaries distinct from process exit;
- workspace transition identities/revisions and safe representations;
- reuse only when the managed boundary can establish it, not guessed from timing.

Use Effect's scoped filesystem handles with checked complete writes and sync at
intent/outcome boundaries. Create the journal and persist its directory entry before
managed mutation; use a single writer per run. A truncated final record is incomplete
history, never a successful outcome. This small local writer is sufficient initially;
EventLog/SQL can replace storage when query/replication needs justify it. Do not put
host mutations into EventLog handlers, whose commit happens after handler success.

Fail history initialization before work. If an outcome write fails after a mutation,
stop subsequent managed work and report unknown/incomplete; do not retry the mutation
to repair history. Record safe projections/source references rather than whole
environments or secret values. Per-run history is not an ownership database and
does not authorize pruning. No automatic retention cleanup is introduced.

The in-memory Workflow engine is enough for fresh finite execution plus durable
history. **No `resume` command is promised by the first profile.** Later recovery
must bind engine persistence, selection/code versions, workspace reconstruction and
domain-specific unknown-outcome reconciliation. Old successful results are history,
not evidence that today's host or artifact is healthy.

## Policy and legacy admission

- Rendering, Ansible automatic execution and later explicit invocation remain
  different planes. `BINS_RUN_BYPASS` gates the first execution lane, not generation
  or every future manual call.
- Concern bypass remains effective in nested managed mutations. Optional skipped
  work is reported; a skipped required producer blocks dependent work.
- Audience admission occurs even under apply-time bypass in the new interface,
  preserving the current typed-action contract. No implicit elevation from `become`.
- A zero legacy exit is process success unless an explicit protocol identifies a
  skip. Do not infer state convergence or parse human output to invent outcomes.
- Opaque script admission needs executable/target/argument/protocol binding, not
  environment receipts, a file catalog, or a claim to know its internals.
- Preserve argument vectors, cwd/setup, wrapper guards, signal forwarding and
  descendants' process lifecycle. Use Effect's process services for new adapters;
  verify compatibility rather than assuming scoped cleanup equals legacy behavior.

# 9. Landing sequence with payoff and deletion

Each checkpoint has useful output and a coherent replacement boundary. These are
commissionable slices, not authorization supplied by this proposal.

| Checkpoint | Useful result and required evidence | What it removes or avoids |
|---|---|---|
| **Selected environment capability** | Importable new-CFR snapshot/resolver plus explicit unregistered proxy Zsh bridge. Reuse real CONFIG exact-file selection/parser. Cover defaults under override, A→B, C with managed args, custom args, pin/reset, untracked/empty/unset, removal-retained, stale/foreign/failed apply. | Avoids another envdefault engine, manifest and fuze dependency; prepares retirement of one proxy default writer. |
| **Shared entry and native composition replacement** | Local bootstrap exposes the host entry; runs against another deployment outside checkout with supported packages. One native ENV operation, real opaque authored bin, and pure aggregate. Broad/narrow selection and imported/direct call agree. Init changes a typed setting consumed twice. Status runs before/after. History and interrupt failure paths are exercised. | Pure aggregate's old `run_all`/flow execution authority is replaced, not shadowed indefinitely. No fifth toy kernel. |
| **Complete domain admission and shared worker closure** | Two complete CONFIGs with same local recipe names remain independent. Preserve normal Zim ownership. Demonstrate frozen audience admission, ENV-before-import, selected worker resources and fanout partial success. Source/packaged providers run the same complete operation. | Removes in-process global-env/root assumptions, central prepared-domain switch for migrated work, and migrated per-deployment shared worker copies. |
| **One real native pipeline cutover** | Extract one authored aggregate only after preserving body order, guards and child argv. Existing fixed aliases select CFR; mismatch/collision/dangling-target fixtures fail before switching. | Deletes its action-session child transport and shell loop; leaves unrelated opaque roots intact. |
| **Material consumer and confext** | Fresh-process packaging of real rendered iface bytes, modes/destinations, artifact status without exposure, custom output basename, and project-/system-owned placement descriptions. | Avoids re-rendering/install-as-packaging and mandatory receipt/asset-database layers. |
| **Broader retirement** | Inventory remaining old callers and perform explicit migration; evidence names what now invokes each authority. | Retire partial `files/flow`, duplicate catalog classification, obsolete action compositor execution and unnecessary per-deployment omnibus claims once their last callers move. |

Put new source in a coherent home, recommended `runtime/cfr/{execution,discovery,
bootstrap,environment}` and domain adapters under `runtime/cfr/domains/{config,
proxy,legacy,materials,confext}`. An alternative is `files/cfr/` beside current
deployed runtime sources; choose one at implementation start, not both. The SDK is
a package/delivery boundary, not an excuse for one new build system per domain.

## No-force/no-prune representation cutover

Before changing entry representations, inventory exact current files, symlink
chains and consumers. Stage/validate the selected provider and complete resource
closure; exercise the proposed entry against the existing deployment binding.
Then replace only explicitly approved entry paths whose observed predecessor still
matches the migration plan. Existing regular files or foreign links refuse ordinary
generation; an explicit migration records their disposition and recoverable prior
state. A dangling replacement target never counts as successful deployment.

Switch one public aggregate's authority at a time. Old unrelated files remain;
stale new-interface entries refuse against the current declaration. Removal is an
enumerated operator migration after callers and status are checked, not background
reconciliation. This directly addresses the reported Zim alias failure class without
claiming a live repair or making no-prune synonymous with broken command exposure.

# 10. Review decisions and acceptance bar

Recommend accepting these design choices together:

1. Native Effect composition, exact collection snapshots and honest outlines;
   no mandatory authored CFR instruction tree.
2. Explicit deployment/provider separation and host ABI package delivery, with
   a terminating local bootstrap and editable source policy.
3. Domain admission/commit ownership; serial mutable run collaboration around
   immutable observations and frozen selected destinations.
4. Durable history first, fresh finite execution first, no general resume promise.
5. Selected ENV as the first useful capability; native pipeline and material tests
   remain required architectural destinations.

The consequential choices still requiring human review are package layout/host
requirements, exact command spelling/default provider locator, the proxy's managed
empty/reset policy before startup adoption, and confext compatibility/output policy.
The recommendations above allow implementation to be commissioned without pretending
these decisions were already made by an older draft.

**The acceptance bar is replacement with retained meaning:** adding a module makes
new work discoverable without modifying a central domain switch; broad/narrow calls
execute the same declared semantics; shared code acts on the selected deployment;
current complete domain transactions remain complete; repeated calls stay repeated;
defaults remain explainable; migrated composition has one execution authority.

### Verification and connections

This draft is design only. Its proposed APIs/examples were not compiled or executed.
Installed Effect source establishes available primitives and hazards, not a working
CFR integration. Earlier passing proxy/environment/domain tests are attributed
evidence and were not rerun. No deployment, systemd action, shell/pane refresh,
provider installation, source implementation or ticket change was performed.

- [Assessment](reset-assessment0.gpt6a.md) — rationale, option comparison and exact
  current-code findings behind these boundaries.
- [Runtime reading map](../runtime-direction/index.md) — distinguishes this proposed
  reset from the recovered lineage and shipped adjacent capabilities.
- [Environment findings](environment1.gpt61sol.md) — concrete behavioral oracle for
  the first slice, with stricter bounds than a general environment manager.
- [CONFIG definitions](../../doc/config/definitions.md) and
  [audience actions](../../doc/actions/README.md) — compatibility meaning to preserve.
- [Sourcing direction](../runtime-sourcing/direction0-syn.gpt61sol.md) — source-policy
  intent integrated here with discovery/bootstrap; receiver portions have since
  acquired the [maintained registry implementation](../../runtime/registry/README.md).
