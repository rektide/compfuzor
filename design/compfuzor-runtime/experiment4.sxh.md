---
type: ArchitectureExperiment
title: CFR backbone experiment 4 — checkout bootstrap across processes and durable material evidence
description: Final scratch probe of one generic module/runner seam across local self-install, pre-write preparation, material realization, fresh-process observation and confext reuse.
resource: /design/compfuzor-runtime/experiment4.sxh.md
tags: [compfuzor, runtime, bootstrap, material, confext, architecture, experiment]
status: draft
generated: { by: 'model:openai/gpt-6-sol#xhigh', at: '2026-09-26' }
verified: { by: 'model:openai/gpt-6-sol#xhigh', at: '2026-09-26' }
sources:
  - id: parent-checkpoint
    resource: /design/compfuzor-runtime/experiments0.gpt6a.md
    title: Experiment-3 assessment and final cross-process assignment
  - id: preceding-probe
    resource: /design/compfuzor-runtime/experiment3.sxh.md
    title: Material interpretation across two layouts and confext
  - id: bootstrap-intent
    resource: /design/compfuzor-runtime/composition-problem0.gpt6a.md
    title: Operator clarification of normal-checkout self-install idea
  - id: prototype
    resource: /.test-agent/cfr-backbone/experiment4/README.md
    title: Executable prototype and reproducibility instructions
---

# CFR backbone experiment 4: one seam through a whole scratch lifecycle

## Question and boundaries

Can **the same small library/runner interface** handle a checkout-local
runtime installing its own fake global entry, preparation before a different
project's first write, material realization, later fresh-process inspection
and build-only confext projection—without Ansible, an already installed
runtime, or a dispatcher full of per-domain cases? Experiment 3 proved real
scratch material and confext output, but its generic-looking kernel typed
`MaterialPlan` directly, its expected hashes lived in a `WeakMap`, and
`buildConfext()` called producers again. The
[parent checkpoint](/design/compfuzor-runtime/experiments0.gpt6a.md#experiment-3--parent-assessment)
asks this last probe to challenge precisely those seams.

Everything executed by this probe lives under ignored
[`experiment4/`](/.test-agent/cfr-backbone/experiment4/README.md); previous
probes were preserved. Every write goes to its `scratch/` fixture trees. The
global executable is a **fake symlink**, `fake-host` is not host `/etc`, and
project preparation is an ordinary **scratch directory plus marker**, **not
btrfs**. No package installation, production file change, global PATH edit,
real project storage migration, networking, host configuration, systemd
activation, mounting or Ansible playbook occurred. This is prototype
self-install behavior, **not implementation of the separate
`compfuzor-runtime-bootstrap` ticket**. Node 26 with native type stripping, a
readable checkout and writable selected scratch directory are explicit
prerequisites; the runtime cannot bootstrap Node or conjure its own checkout
path on a foreign host.

## Two architectures in this final pressure test

1. **Host-controller driver with scenario-specific commands.** A script knows
   `install → prepare → render → inspect → package`, calls one special
   callback per step, and keeps paths/hashes in process. This could pass a
   single demo but does not give independent modules a common place to
   contribute programs or data, fails fresh-process observation, and may
   accidentally use the *target project's* not-yet-created tree to bootstrap.
2. **Domain-agnostic selection/dispatch plus contributed domain services
   (probed).** The kernel collects records keyed by contract, binds a chosen
   provider for each requested service, and dispatches program IDs without
   interpreting material or lifecycle semantics. Bootstrap, preparation,
   material and confext are **different modules on that one registration
   seam**. The storage/material/packaging modules use a shared file-operations
   provider but own their own inputs and results. The controller still supplies
   a checkout location and an external request before the project exists.

The second is not a proof of a complete plugin architecture. It is a runnable
test that multiple domains can occupy the same interface without turning all
of them into an arbitrary universal `Action` or `Material` type.

## Exact library, author and frontend surfaces

[`kernel/library.ts`](/.test-agent/cfr-backbone/experiment4/kernel/library.ts)
is intentionally ignorant of file destinations, confext, readiness and
bootstrap. Its authored surface is:

```ts
type Module = {
  id: string;
  data?: { contract: string; id: string; value: unknown }[];
  providers?: { contract: string; id: string; value: unknown }[];
  programs?: {
    id: string; description: string;
    run(context: Runtime, input: Record<string, unknown>): Promise<unknown>;
  }[];
};
type ContributionSet = { modules: string[]; bind: Record<string, string> };

// Generic Runtime: collect<T>(contract), service<T>(contract),
//                  call(programId, input), record(event, details).
// Every authored call runs; there is no automatic program/query memoization.
```

An externally written request supplies `contract:1`, selected module IDs,
bindings, `sandboxRoot`, controller trace/counter paths, and (only when needed)
either `fakeGlobal.entry` or explicit `target:{project,fakeHost}` and render
inputs. [`checkout/modules.ts`](/.test-agent/cfr-backbone/experiment4/checkout/modules.ts)
registers a checkout's trusted modules at import; the
[`checkout/cli.ts`](/.test-agent/cfr-backbone/experiment4/checkout/cli.ts)
frontend parses only `run PROGRAM REQUEST.json`, validates the prototype's
scratch boundary and runtime-contract version, loads selected modules, then
invokes the named program. **It has no `if (program === "confext.build")` or
bootstrap-vs-material dispatcher.** Domain-neutral `state:blocked` gets exit
code **3**; incompatible contract and other bounded refusals get **2**. The
frontend is launched with `node <entry>.ts` rather than as a PATH executable;
shebang, bundling, distribution and global upgrade behavior remain unproved.

Examples of real authored contributions:

```ts
// domains/bootstrap.ts (project root is NOT required)
{ id: "runtime.install", async run(ctx) {
    return ctx.service<FileOps>("files/v1").ensureSymlink(
      ctx.checkoutEntry, ctx.request.fakeGlobal!.entry);
} }

// domains/preparation.ts: composed program with two actual observations
{ id: "project.observe-around", async run(ctx) {
    const before = await ctx.call("material.inspect");
    const convergence = await ctx.call("project.converge");
    const after = await ctx.call("material.inspect");
    return { before, convergence, after };
} }

// modules/iface.ts: contributing *data*, with an explicit producer only
// for extra-addr. Same playbook-derived destinations and representative
// bytes as experiment 3, but via a generic data contract.
{ contract: "material.file/v1", id: "iface.extra-addr.eno1.dropin",
  value: { destination: { root: "networkd", relative:
    "en.network.d/systemd-iface-extra-addr-eno1.conf" },
    projectName: "extra-addr.conf", mode: 0o644,
    source: { kind: "program", id: "iface.render-extra" } } }
```

The abbreviated snippets omit checks; use actual
[`domains/bootstrap.ts`](/.test-agent/cfr-backbone/experiment4/domains/bootstrap.ts),
[`domains/preparation.ts`](/.test-agent/cfr-backbone/experiment4/domains/preparation.ts),
[`domains/material.ts`](/.test-agent/cfr-backbone/experiment4/domains/material.ts),
[`domains/confext.ts`](/.test-agent/cfr-backbone/experiment4/domains/confext.ts)
and [`modules/iface.ts`](/.test-agent/cfr-backbone/experiment4/modules/iface.ts)
for exact code. These domain services depend on each other's typed contracts
where appropriate; the *kernel* does not import them.

One reusable capability underpins several concerns:
[`files/v1`](/.test-agent/cfr-backbone/experiment4/kernel/file-ops.ts)
offers scratch-local `ensureSymlink`, `ensureDirectory`, `write` and `copy`.
Bootstrap uses it to expose the checkout, preparation to create a marker,
material realization to write bytes/receipt, and confext to copy **existing**
project bytes. This is reuse below the programs, not recursive invocation of
an already installed global command.

## Run and observable evidence

From the repo root (no new package dependencies):

```sh
node .test-agent/cfr-backbone/experiment4/demo.ts
# optional existing-tool type check
pnpm exec tsgo --ignoreConfig --noEmit --target esnext --module nodenext \
  --moduleResolution nodenext --allowImportingTsExtensions --types node \
  .test-agent/cfr-backbone/experiment4/demo.ts \
  .test-agent/cfr-backbone/experiment4/checkout/cli.ts
```

Both commands passed. [`demo.ts`](/.test-agent/cfr-backbone/experiment4/demo.ts)
uses `spawn()` for **real, separate Node processes**, printing every relevant
selected plan, result, inspection, receipt, confext release/payload/manifest,
and final trace. A full generated capture is ignored under
`experiment4/scratch/demo-output.txt`. Excerpts below are condensed; the
prototype's exit codes and state distinctions are real output, not assertions
of production integration.

### Bootstrap cannot depend on its own installation

Before installation the controller's `invokeInstalled()` reports a bounded
`fake global entry missing; run checkout-local runtime.install first`. A
missing command cannot emit its own error; **this is irreducible controller
glue**, not a special branch in the runtime. The driver then invokes the
checkout's own local `cli.ts` with `runtime.install`; the contributed program
creates the actual scratch symlink:

```text
scratch/fake-global/bin/cfr-prototype.ts ->
  <this checkout>/.test-agent/cfr-backbone/experiment4/checkout/cli.ts
local runtime.install: state=complete, result=created
local runtime.install again: state=complete, result=unchanged
unrelated regular fake-global entry: refused (exit 2), original bytes unchanged
```

No target project exists during these invocations. A *new subprocess* through
the installed symlink then plans the explicitly supplied absent
`scratch/target-project` (3 materials, mode `0644`, resolved destinations and
origin module, known hash for literal bytes; extra-addr's produced bytes not
yet available). The runtime reports three different locations:

```text
checkoutEntry realpath: .../experiment4/checkout/cli.ts
invokedVia:          .../experiment4/scratch/fake-global/bin/cfr-prototype.ts
target.project:      .../experiment4/scratch/target-project
```

The frontend refuses request contract `99` with `runtime contract 99
unsupported; this checkout supports 1` (exit 2, project still absent). No
assertion here tests installed-version upgrade or compatibility beyond this
single prototype format. A real checkout must still expose its normal
`runtime/compfuzor-runtime.mjs` using an agreed packaging/install mechanism;
the operator's `cf-r` is an **idea**, not a pre-existing utility we found.

### Before the project's first write

`target.project` is supplied by a controller request in `scratch/controller`,
**outside** the not-yet-created target. `project.converge` composes
`project.prepare → material.realize`; direct `material.realize` also checks
the preparation marker. With `skipPreparation:true`, the new project's run
returns `{state:"blocked"}` **exit 3**, creates no target and does not invoke
the byte producer. Direct realization without a marker likewise returns
blocked/exit 3. The supported preparation here creates an ordinary directory
and `project/.cfr-prepared.json`; it refuses unprepared nonempty roots rather
than silently migrating them. This is **not** evidence of btrfs subvolume
creation or any storage prerequisite on a real host.

The successful call is `project.observe-around`. Its actual program trace is:

```text
project.observe-around
  material.inspect          -> materialHealth:missing
  project.converge
    project.prepare          -> before-first-write, marker-written
    material.realize
      iface.render-extra     -> producer count 1 (controller scratch)
      material.before-write  -> static-only and extra-addr project bytes
      material.receipt-written
  material.inspect          -> materialHealth:healthy
```

The shared cross-process trace orders `prepare.before-first-write` before
`prepare.marker-written`, both before the first `material.before-write` for
that target. The demo asserts two real `material.inspect` invocations around
the mutation—experiment 2's implicit deduplication would have been wrong.
Trace writes and the producer counter are in **controller scratch**, not
premature writes inside the target.

### Persistent truth and build-only reuse

After explicit realization,
`target-project/state/materials.receipt.json` persists, per material:
logical ID, intended destination, project-relative byte path, mode, SHA-256,
producer ID when present, and a digest of the selected declaration plus
relevant inputs. A fresh subprocess reconstructs the declaration/placement
plan, reads this receipt **from disk**, checks actual byte hashes and modes,
and reports:

```text
materialHealth: healthy
exposureHealth: missing
iface.static-only.ens3.network: material=healthy, exposure=missing
iface.extra-addr.eno1.dropin: material=healthy, exposure=missing
```

There is deliberately **no fake-host publication**; a healthy project-owned
material is eligible for an artifact without a host exposure. Presence is the
only exposure observation implemented here, **not proof of correct symlink or
copy destination health**. `confext.plan` evaluates authored ordered
include/exclude/reinclude rules against *intended* `/etc` destinations and
selects standalone static-only and extra-addr drop-in, excluding an explicitly
illustrative unrelated drop-in.

A fresh `confext.build` subprocess calls the independently contributed
builder service. It reads the persisted receipt, validates *selected*
materials against the real files, copies those **already existing** project
bytes into a directory artifact and writes a sidecar manifest. It never calls
`iface.render-extra`. Actual results:

```text
scratch/target-project/outputs/iface-final/
  etc/extension-release.d/extension-release.iface-fixture
  etc/systemd/network/10-ens3-static-only.network
  etc/systemd/network/en.network.d/systemd-iface-extra-addr-eno1.conf
scratch/target-project/outputs/iface-final.manifest.json

release:
  ID=_any
  CONFEXT_SCOPE=system portable
both payloads: regular project-byte copies, mode 0644
producer calls after production, inspect, plans and THREE successful bundles: 1
fake-host existing marker SHA-256 unchanged; selected fake-host files absent
```

The artifact is **directory-form**; no image/verity/DDI or installation is
implied. Confext release location and `_any`/`CONFEXT_SCOPE` policy carry
forward the local-systemd source checks in
[experiment 3](/design/compfuzor-runtime/experiment3.sxh.md#build-only-directory-form-confext-from-intended-destinations).
The builder checks health before considering a named output; it refuses to
overwrite an existing artifact and never prunes old outputs.

The failure and reuse tests are important rather than decorative:

| Challenge, each in fresh installed-entry process | Result | Producer counter |
|---|---|---:|
| Tamper selected extra-addr bytes after one valid bundle exists | `material.inspect: drift`; another build with that prior output name **blocked, exit 3**; old artifact cannot masquerade as this build's success | 1 |
| Delete selected file | `material.inspect: missing`; new build **blocked, exit 3**, no output | 1 |
| Change requested producer input without production | `material.inspect: stale-intent`; build **blocked, exit 3**; no implicit regeneration | 1 |
| Drift only the *excluded* fixture material | Overall project status reports drift; confext explicitly checks only selected IDs and completes | 1 |
| Explicitly call `material.realize` with new producer input | New project bytes + receipt; new input status healthy; old artifacts remain (no auto-prune) | **2** |

If an I/O error occurs midway through material writes or bundle staging,
this toy is **not transactional**. Persisting a receipt only after writing
files improves fresh inspection but does not guarantee atomic publication.
Artifact provenance is a local record of selected inputs and bytes, not a
cryptographic attestation against a hostile editor who can modify both files
and receipt. A producer implementation change without changed declaration or
input can also leave the fingerprint unchanged: code/version pinning remains
open.

## What four sequential probes actually changed

| Probe | Gain retained | Important correction or limit |
|---|---|---|
| [1](/design/compfuzor-runtime/experiment1.sxh.md) | Independently provided capabilities; consumers author programs; CLI path is a *view* of subject selection | Exactly-one per subject and hard-coded source admission incorrectly obstruct many additive contributors. |
| [2](/design/compfuzor-runtime/experiment2.sxh.md) | Choose a provider separately from collecting contributions; programs themselves are discoverable contributions; caller-selected contribution set | Global `seen(program,query)` suppressed legitimate `status → change → status`; opaque sorted entries cannot resolve material ownership or prerequisites. |
| [3](/design/compfuzor-runtime/experiment3.sxh.md) | Desired materials give shared destination, mode, producer and source knowledge; domain interpreter yields *real* opposed links and build-only confext | Material-typed kernel, in-memory WeakMap hashes and regeneration-on-build were not a credible cross-process backbone. Scratch symlinks do not authorize real networkd exposure. |
| **4 (here)** | Generic keyed module/data/service/program seam serves bootstrap, preparation, material and confext; local symlink installs without an existing global runtime; receipts support fresh health and reuse | The modules/index and frontend are still trusted checkout code and a fixed prototype. Safety, discovery, distribution, real host policy and project write transactionality remain unsolved. |

**Architectural checkpoint:** the smallest convincing candidate is *not* a
universal route graph or a generic task queue, but a library that admits
different kinds of domain contribution (data, replaceable providers, programs)
and binds their chosen set to an explicit invocation context. Domains own
their interpretation and postconditions; the runner owns selection, call
identity/occurrence, attribution and dispatch. A checkout may provide a local
entry that installs a shared entry without invoking itself via an unavailable
global path. Preparation, bytes, exposure and artifact are **distinct
outcomes**, not synonyms for `apply`.

This is **architectural learning, not acceptance of the prototype's API or
authorization for production implementation**. Still to decide with the
operator: contribution-set discovery and admission (the final checkout index
is statically authored and does not load arbitrary project TS dynamically),
cross-domain contract/version negotiation, module trust and import-time
effects, which operations are data versus programs, material ownership and
accessible representation per target consumer, split domain-service
granularity, atomic/locked writes, actual path-symlink containment, durable
receipts after upgrades, lifecycle and concern-specific bypass semantics,
project/host scope and multiple deployments, coexistence of LINKS copies
with extension overlays, production runtime packaging/installation/upgrade,
and image/DDI formats or actual systemd validation. Node and target-root
bootstrap inputs remain genuinely external. Neither a fake symlink nor a
marker claims to implement real host permissions or btrfs.

## Cross-references

- [Sequential experiment plan](/design/compfuzor-runtime/experiments0.gpt6a.md)
  — operator-imposed stop after this fourth, parent-reviewed probe and the
  corrections this implementation intentionally tests.
- [Experiment 3 report](/design/compfuzor-runtime/experiment3.sxh.md) —
  physical layout/confext evidence carried forward, and three cross-process
  problems (material kernel coupling, WeakMap, regeneration) tested here.
- [Runtime composition problem](/design/compfuzor-runtime/composition-problem0.gpt6a.md)
  — distinguishes the operator's `cf-r` normal-checkout self-install *idea*
  from an existing global executable; the real ticket is separate.
- [Iface declarations](/systemd-iface-static-only.etc.pb) ·
  [extra-addr declarations](/systemd-iface-extra-addr.etc.pb) — actual
  source shapes behind these **manually substituted examples**, not Ansible
  render/test evidence.
- [Confext research](/design/confext/build-inputs1.fx.md) — confext-specific
  paths/metadata and mode discrepancy; build-only remains separate from
  installation and activation.
