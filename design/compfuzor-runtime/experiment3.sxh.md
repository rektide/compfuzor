---
type: ArchitectureExperiment
title: CFR backbone experiment 3 — material descriptions, opposing layouts and build-only confext
description: Executed scratch filesystem probe of contributed desired material interpreted into reversed ownership layouts and a directory-form confext without host publication.
resource: /design/compfuzor-runtime/experiment3.sxh.md
tags: [compfuzor, runtime, composition, desired-state, layout, confext, experiment]
status: draft
generated: { by: 'model:openai/gpt-6-sol#xhigh', at: '2026-09-26' }
verified: { by: 'model:openai/gpt-6-sol#xhigh', at: '2026-09-26' }
sources:
  - id: checkpoint
    resource: /design/compfuzor-runtime/experiments0.gpt6a.md
    title: Parent assessment of experiment 2 and experiment 3 assignment
  - id: prior
    resource: /design/compfuzor-runtime/experiment2.sxh.md
    title: Choose-versus-collect result and material/order counterexamples
  - id: static
    resource: /systemd-iface-static-only.etc.pb
    title: Actual standalone .network ETC_FILES/LINKS declaration
  - id: extra
    resource: /systemd-iface-extra-addr.etc.pb
    title: Actual networkd drop-in ETC_FILES/LINKS declaration
  - id: upstream-systemd
    resource: /home/rektide/archive/systemd/systemd/src/basic/os-util.c
    title: Local systemd source for confext extension-release location
---

# CFR backbone experiment 3: material is not a scheduled call

## Question and bounded test

Experiment 2 separated *choosing one provider* from *collecting many entries*,
but almost every entry remained an opaque executable. The
[parent checkpoint](/design/compfuzor-runtime/experiments0.gpt6a.md#experiment-2--parent-assessment)
also rejected its global `seen(program,query)` optimization: an authored
`status → change → status` must observe twice. This experiment tests the
previously unprobed alternative: **independent modules contribute desired
materials with explicit intended destinations, modes and byte sources; a domain
interpreter derives physical placements and a build-only artifact from the
same descriptions.** Does this make CFR a stronger library/runner backbone
than a larger scheduler?

Everything executable is under ignored
[`experiment3/`](/.test-agent/cfr-backbone/experiment3/README.md); experiment
1 and 2 were preserved. All file operations are under
`.test-agent/cfr-backbone/experiment3/scratch`. `fake-host/etc` is not `/etc`.
No Ansible run, live network/systemd operation, storage migration, install,
confext placement into system directories, merge, activation or mount took
place. The output is an actual **directory-form confext artifact** under
scratch, not a placeholder for an unimplemented image-format choice. Image
and DDI formats are separate untested options, not required to count this
directory-form artifact as a completed build.

## Input fidelity: what came from the real playbooks

I read [`systemd-iface-static-only.etc.pb`](/systemd-iface-static-only.etc.pb#L53-L76)
and [`systemd-iface-extra-addr.etc.pb`](/systemd-iface-extra-addr.etc.pb#L46-L80)
read-only. This probe **manually substitutes representative variables**; it
does **not** claim to be an Ansible render or reproduce either playbook's
runtime discovery/guard tasks:

| Authored fact | Representative input here | Material result |
|---|---|---|
| static-only is a standalone first-match `.network` replacing DHCP | `INSTANCE=ens3`, `ADDRESS_CIDR=203.0.113.10/24`, `GATEWAY=203.0.113.1`, `DNS=[193.110.81.0]`, `NAME=systemd-iface-static-only-ens3` | `iface-static-only.network` intended at `/etc/systemd/network/10-ens3-static-only.network` |
| extra-addr is a drop-in **preserving DHCP** | `INSTANCE=eno1`, `NETWORK_FILE=en` supplied **explicitly**, `ADDRESS_CIDR=192.168.1.8/22`, `NAME=systemd-iface-extra-addr-eno1` | `extra-addr.conf` intended at `/etc/systemd/network/en.network.d/systemd-iface-extra-addr-eno1.conf` |

The first set of substitutions differs from the playbook defaults deliberately
(documentation/example address, no live machine). The second uses the
playbook's overridable explicit basename, not `networkctl status`; no target
interface was probed. An unrelated third desired file, from
[`modules/unselected.ts`](/.test-agent/cfr-backbone/experiment3/modules/unselected.ts),
exists only to demonstrate negative package selection; it is **not** an iface
playbook output. Real ETC_FILES currently default to **0660** and LINKS copy
delivery inherits that mode before `apply.sh` normalizes the host file to
**0644**, as traced in
[`build-inputs1.fx.md`](/design/confext/build-inputs1.fx.md#22-destinations-links--linksjson--runtime-delivery).
The probe explicitly chooses `0644` for its intended material and artifact
instead of silently inheriting a render-time file mode.

## The changed backbone, not a `confext.build` callback

[`kernel/model.ts`](/.test-agent/cfr-backbone/experiment3/kernel/model.ts)
distinguishes **desired material** from **producers**, **programs**, and the
chosen **material domain interpreter**. A caller-selected `ContributionSet`
replaces experiment 2's ambiguous word `Scope` (which already means
system/user elsewhere in Compfuzor). The set includes the relevant modules
once; the interpreter binding chooses one implementation. The generic
[`kernel/library.ts`](/.test-agent/cfr-backbone/experiment3/kernel/library.ts)
registers/selects/discovers modules and invokes contributed programs. It has
no hard-coded `ready`, `/etc`, link, confext or status semantics and **does not
memoize program calls**.

Actual authored interface excerpts:

```ts
type Material = {
  id: string; module: string; description: string;
  at: { root: "networkd" | "etc"; relative: string }; // intended destination
  projectName: string; mode: number;
  content: { kind: "literal"; bytes: string } | { kind: "producer"; id: string };
};
type Producer = {
  id: string; dependsOn: string[];
  produce(values: Readonly<Record<string, string>>): Promise<string>;
};
type ContributionSet = {
  id: string; modules: string[]; bind: { material: string };
};
```

[`modules/static-only.ts`](/.test-agent/cfr-backbone/experiment3/modules/static-only.ts)
contributes literal bytes; [`modules/extra-addr.ts`](/.test-agent/cfr-backbone/experiment3/modules/extra-addr.ts)
contributes an independently authored material and two producers. Its
`a.extra.render` explicitly **depends on** `z.extra.address-line`, so
material production is ordered `z → a` despite the opposite lexical ID order.
This is a small *domain-local prerequisite among byte producers*, not a new
global dependency graph of all Compfuzor effects. The intended drop-in
destination is statically resolved from explicit `NETWORK_FILE=en`, so planning
can inspect it without calling either producer. Runtime discovery would change
that availability and requires an explicit lifecycle decision later.

The selected domain provider in
[`domain/material.ts`](/.test-agent/cfr-backbone/experiment3/domain/material.ts)
does the work a generic runner cannot honestly infer: binds logical roots to
physical scratch roots, detects resolved destination collisions, orders
required producers, places file bytes and links, inspects real owner/exposure
state, selects by intended `/etc` destination, and builds the confext. The
distinct, independently contributed
[`programs/material.ts`](/.test-agent/cfr-backbone/experiment3/programs/material.ts)
offer `material.status`, `material.publish`, `material.observe-around`, and
`confext.build`. Thus the *same* declared material is read by several
consumers; confext is **one projection of material**, not a magic scheduler
entry. The domain interpreter is admittedly powerful; a future implementation
should factor shared filesystem primitives and retain domain ownership of
interpretation, rather than enshrine this toy monolith as a universal file IR.

Compare responsibility allocations:

| Alternative | Who resolves paths, dependencies and success? | What the probe showed |
|---|---|---|
| Generic runner owns all files, links, package filters, readiness | Runner must understand destination namespaces, domain claims and two output kinds; generic DAG/phase machinery expands with every domain | Rejected as an experiment-3 core: hides real semantics in a supposedly generic scheduler |
| Contributed desired-state products + a selected domain interpreter; generic runner only discovers/invokes programs | Material domain owns ownership, layout, byte production and observation; programs own when to publish/package/inspect | **Probed.** Distinct status/build/publish outcomes from the same descriptions; generic runner records calls without interpreting `healthy` or `blocked` |

The earlier action/offer model remains valuable **alongside** data products:
some activities are opaque legacy scripts, lifecycle preparation, or domain
producers. This experiment does **not** convert all those into universal
resource descriptions. It argues for *complementary contributed descriptions
and callable capabilities*, with explicit handoff between them.

## Reproduction and actual evidence

Run from the repository root (Node 26, no new packages):

```sh
node .test-agent/cfr-backbone/experiment3/demo.ts
# optional: existing dev typechecker, no package changes
pnpm exec tsgo --ignoreConfig --noEmit --target esnext --module nodenext \
  --moduleResolution nodenext --allowImportingTsExtensions --types node \
  .test-agent/cfr-backbone/experiment3/demo.ts
```

Both commands passed. The demo prints full descriptions, plans, actual bytes,
`readlink` results and file modes, status results, package selection decisions,
and collision/bypass refusals. The generated capture is ignored
`experiment3/scratch/demo-output.txt`; the report excerpts below are
condensed, not a replacement for the executable output.

### Same data; genuinely opposite ownership and links

For **system-owned**, the scratch file
`system-first/fake-host/etc/systemd/network/10-ens3-static-only.network`
contains bytes and has mode `0644`; the
corresponding `.../system-first/project/material/iface-static-only.network`
is a real symlink with:

```text
readlink(project/material/iface-static-only.network)
  ../../fake-host/etc/systemd/network/10-ens3-static-only.network
```

For **project-owned**, the same literal material's bytes have mode `0644` at
`.../scratch/project-first/project/material/iface-static-only.network`, while
the fake system destination is now the symlink:

```text
readlink(fake-host/etc/systemd/network/10-ens3-static-only.network)
  ../../../../project/material/iface-static-only.network
```

The extra-addr material follows the same inversion at its *different*
drop-in destination, including real bytes:

```ini
# static secondary address (systemd-iface-extra-addr-eno1); DHCP stays authoritative
[Network]
Address=192.168.1.8/22
```

The demo checks `lstat().isSymbolicLink()`, `readlink()` resolution to the
declared owner, byte-for-byte reading through the link, and owner-file
`stat().mode & 0777 === 0644` under both layouts. It does **not** claim that
real networkd can traverse a private project path: both source playbooks
currently specify **copy-only** host LINKS and explain why. The scratch
project-owned symlink is a *physical feasibility experiment*, not a safe live
networkd publication choice. Conversely, system-owned bytes plus project
symlink do not make a project tree portable. Link direction and byte ownership
are explicit; correctness for each real consumer still needs its own delivery
representation (copy, accessible link, extension, etc.).

### Status before → publish → status after, with actual postconditions

The contributed `material.observe-around` calls `material.status`, then
`material.publish`, then **calls `material.status` again**; no global
program/query `seen` map suppresses the second observation. In both layouts:

```text
invocations: material.observe-around, material.status,
             material.publish, material.status
before.state: missing
published.state: complete
published.produced: [z.extra.address-line, a.extra.render]
after.state: healthy
ASSERT status before and after runs twice, with changed observation: PASS
```

Subsequently changing the project-owned extra-addr owner's real file mode to
`0600` makes a separate status call report `drift`; restoring `0644` restores
the expected referent mode. Neither `healthy` nor `drift` is hard-coded in the
generic runner. Domain inspection checks presence, symlink direction, mode,
and (for bytes realized by this in-memory plan) content digest. No live
network readiness is inferred from file presence; these are filesystem
postconditions only.

### Build-only directory-form confext from intended destinations

The same selected material definitions, with project-owned bytes but **no
host exposure**, feed `confext.build`. The limited matcher is *not* full
gitignore: `include|exclude` rules match canonical intended `/etc/...` paths;
`*` means one segment, `**` any suffix, later matching rule wins, default is
excluded; no filesystem walk, hidden-file policy, symlink traversal, arbitrary
regex, or negation syntax. Actual rule sequence:

```ts
[
  { effect: "include", dest: "/etc/systemd/network/**" },
  { effect: "exclude", dest: "/etc/systemd/network/en.network.d/**" },
  { effect: "include", dest: "/etc/systemd/network/en.network.d/systemd-iface-extra-addr-eno1.conf" },
]
```

Selection explanation reports static-only `include`, extra-addr
`include → exclude → include` (selected), and the fixture-only unrelated
drop-in `include → exclude` (not selected). The completed actual output is:

```text
scratch/build-only/outputs/iface-fixture/
  etc/extension-release.d/extension-release.iface-fixture
  etc/systemd/network/10-ens3-static-only.network
  etc/systemd/network/en.network.d/systemd-iface-extra-addr-eno1.conf
scratch/build-only/outputs/iface-fixture.manifest.json

release file (0644):
  ID=_any
  CONFEXT_SCOPE=system portable
payload: both regular files, mode 0644, bytes equal project sources
manifest: selected material IDs, intended destinations, SHA-256 and modes
```

`ID=_any` intentionally avoids claiming compatibility with a particular host
OS; `CONFEXT_LEVEL`/`VERSION_ID` are not required for `_any`. `CONFEXT_SCOPE`
is limited to `system portable`. The **confext-specific** release path under
`etc/extension-release.d` and keys follow the local systemd sources
[`os-util.c` L41–46](~/archive/systemd/systemd/src/basic/os-util.c),
[`extension-util.c` L24–25,L37–54,L69–80](~/archive/systemd/systemd/src/shared/extension-util.c)
and the independent [confext research](/design/confext/build-inputs1.fx.md#1-corrections-to-archaeology0fxmd-5).
I checked local systemd/mkosi checkout availability first and checked each
checkout's `llms.txt` (absent) before reading source. This probe verifies a
valid-*shaped* directory and bytes against these sources; it does **not**
prove that an actual systemd-confext command has validated, merged, mounted or
activated the artifact on a host.

Before build, a scratch fake-host file `preserved-before-build.conf` had hash
`1b8a216cb43f2c1b1eada4342a617e150d3d933e40294f98cbcd93fa50371fc2`;
the full fake-host tree listing/hashes were **identical afterward**, and no
unselected project file was produced. Neither published host links nor fake
host configuration changed during this build.

## Domain-local refusals, inspection boundary, and what is still false

1. **Physical collision:**
   [`modules/conflict.ts`](/.test-agent/cfr-backbone/experiment3/modules/conflict.ts)
   adds `fixture.rival-ens3` at `root:etc` and
   `relative:systemd/network/10-ens3-static-only.network`, whereas static-only
   declares `root:networkd` and `relative:10-ens3-static-only.network`.
   Distinct module/material IDs and logical root expressions resolve to the
   **same physical fake-host path**. Material-domain planning fails with
   `physical destination collision` between `iface.static-only.ens3.network`
   and `fixture.rival-ens3`, before files or producer effects exist. Collision
   detection compares resolved host **and** project material paths, not merely
   matching authored IDs. It does not yet canonicalize existing symlinked
   parents, detect all ancestor/descendant conflicts, or arbitrate across
   multiple independently selected deployments.
2. **Required production bypass:** when `a.extra.render` is suppressed, the
   confext program returns `state:blocked, reason:"required material production
   bypassed: a.extra.render"`. Producer dependency closure is validated
   *before* writes; the demo verifies no partial project material, no outputs
   and no fake-host changes. Bypassing required material cannot be a fake
   successful artifact. Other sorts of I/O failure during publication could
   leave partial files here; this is **not** a transactional engine.
3. **What a plan knows:** before producers run, the plan can show exact
   destination paths, owning modules, mode, link direction, content provenance,
   required producer order and the hash of the **literal** static-only file.
   It cannot know the final hash of producer-backed extra-addr bytes (printed as
   `sha256KnownAtPlanning:null`), prove the script is pure, validate access
   control for real networkd, or infer a host's live DHCP/interface state.
   Materialized hashes and project-to-confext mapping are observed afterward.
   `NETWORK_FILE=en` is supplied explicitly; runtime-only discovery would
   further delay knowledge of the destination and could invalidate collision
   checks before the first write. That is an architectural decision, not a
   detail for this toy to hide.

**The central revision to experiment 2:** collecting material declarations
is more useful than collecting opaque commands when different consumers need
the same source/destination knowledge. Producer dependencies can be resolved
locally without pretending lexical IDs are causality. Domain-specific result
interpretation can stay out of the generic runner. Experiment 2's positive
choose-versus-collect and independently contributed programs survive, but its
global repeated-call suppression is rejected outright. The representation
still needs **two complementary contributions**: inspectable desired products
and callable producers/operations for the things descriptions alone cannot do.

## Architectural checkpoint / proposed experiment 4 pressure

This probe supports a library of selected declarations and contributed
programs, with a selected domain interpreter compiling a meaningful plan and
reporting outcomes. It does **not** prove universal relatability, a deployable
project symlink for networkd, packaging of secrets or permissions beyond the
chosen simple file modes, image/DDI production, conflict-free coexistence
with existing LINKS copies, portability of embedded paths, idempotent
republication, host/systemd validation, or bootstrap.

The next highest-yield **parent-selected** experiment toward the user goal
would press the *whole lifecycle boundary*, not add more route aliases:
can an ordinary checkout expose its runtime using its **own local code with no
pre-existing global runtime or Ansible**, and can that runtime distinguish
bootstrap location from a not-yet-created deployment, perform an early
pre-write preparation in scratch, then materialize/package a representative
project from one selected declaration set? Force a missing-runtime or
incompatible-contract case and an explicit skip/incomplete outcome. Test only
inside isolated fake roots; do not use real btrfs/networking/systemd or install
to global locations. **This is a question for parent assessment, not
authorization to start experiment 4.**

## Cross-references

- [Sequential experiments and parent checkpoint](/design/compfuzor-runtime/experiments0.gpt6a.md)
  — experiment-3 constraints and the explicit rejection of implicit program
  memoization.
- [Experiment 2](/design/compfuzor-runtime/experiment2.sxh.md) — choose vs
  collect, program contributions and the earlier inability to explain real
  material ownership or order.
- [Original runtime composition problem](/design/compfuzor-runtime/composition-problem0.gpt6a.md)
  — single-tree aspiration, manual apply and bootstrap clarification; this
  scratch experiment is evidence about representation, not migration policy.
- [Confext byte/format investigation](/design/confext/build-inputs1.fx.md) —
  corrected confext format, source modes, and direct iface byte provenance;
  distinguishes this directory build from installation or activation.
- [Contained layout precedent](/vars/containered.yml) — prior inversion of
  structural family links, which this probe renders concrete in both
  directions without treating "containered" as the name of a universal
  capability.
