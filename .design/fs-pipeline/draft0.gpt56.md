---
type: Design
title: Filesystem pipeline option space
description: Independent design options for evolving compiled artifacts into a modern filesystem apply pipeline.
resource: https://github.com/rektide/compfuzor/blob/main/.design/fs-pipeline/draft0.gpt56.md
tags: [compfuzor, design, filesystem, artifacts, ansible, pipeline]
status: draft
generated: { by: llm:gpt56, at: 2026-08-19 }
stale_after: 2026-11-19
sources:
  - id: link-script-draft2
    resource: https://github.com/rektide/compfuzor/blob/main/.design/link-script/draft2-0.gpt56.md
    title: Compiled artifacts and deferred link plans
  - id: pipeline-memo
    resource: https://github.com/rektide/compfuzor/blob/main/doc/pipeline-and-intent-prefix-memo.md
    title: Pipeline and intent prefix memo
  - id: prefix-review
    resource: https://github.com/rektide/compfuzor/blob/main/doc/prefix-review.md
    title: Prefix review gap analysis
---

# Filesystem pipeline option space

## Status and purpose

The deferred LINKS work introduced a compiled artifact seam, but deliberately
stopped short of replacing the filesystem executor. This document captures the
larger design space for future consideration. It does not select an
implementation.

The options are presented separately because they optimize for meaningfully
different outcomes:

- minimal disruption;
- fewer Ansible orchestration steps;
- fewer target-side module invocations;
- atomic deployment;
- deferred activation;
- mixed execution chosen by artifact semantics.

Combining them too early would conceal their individual costs. The purpose of
draft0 is to preserve the option space, identify the evidence each direction
needs, and establish shared evaluation criteria.

## What changed, and what did not

### Before compiled artifacts

Filesystem declarations flowed almost directly from public variables into
effects:

```text
FILES / ETC_FILES / VAR_FILES / ...
  -> _multi variable-name discovery
  -> one fs_hierarchy.tasks include per active family
  -> family-local destination expressions
  -> file/copy/lineinfile effects
```

Different writers had different destination rules. `FILES`, hierarchy copy
entries, hierarchy line entries, and old LINKS each interpreted `dest`, `name`,
`src`, absolute paths, and templates somewhat differently.

The hierarchy executor also owns several responsibilities at once:

- discover whether a family is active;
- select materialized and exposure roots;
- calculate bypass state;
- probe root and structural-link existence;
- create family roots;
- create deployment hierarchy links;
- create declared subdirectories;
- interpret file content declarations;
- run line edits;
- calculate privilege and ownership;
- write artifacts.

### The current intermediate state

The link-plan implementation added one batch compilation step:

```text
raw FILES / *_FILES
  -> compile_artifacts
  -> _ARTIFACTS
       families
       copies
       lines
  -> current fs_base / fs_hierarchy executor
```

`_ARTIFACTS` now gives every file record:

- artifact family and fsh kind;
- writer classification (`copy` or `line`);
- identity and origin;
- materialized root;
- exposure root at family level;
- family-relative destination when available;
- one `resolved_dest` shared by filesystem application and link synthesis.

This removed destination disagreement and made `FS_CONTAINERED` visible to link
generation. It also created flattened `copies` and `lines` collections.

The filesystem apply path remains mostly family-oriented:

- `_multi.tasks` still discovers variables and includes
  `fs_hierarchy.tasks` once per active family;
- `fs_hierarchy.tasks` still begins with a family-local `set_fact`;
- root and exposure paths are still probed with `stat`;
- subdirectories are still interpreted from raw `<KIND>_DIRS` variables;
- copy content, source selection, modes, ownership, backup, `once`, and
  privilege are still resolved in task-local Jinja;
- `fs_base.tasks` remains separate from hierarchy-family execution;
- flattened `_ARTIFACTS.copies` and `_ARTIFACTS.lines` are not yet the apply
  interface.

The result is a useful but incomplete handoff: destination identity is compiled,
while much of artifact meaning remains embedded in the raw `item` carried by
each compiled record.

## The architectural question

The broad question is:

> How far should compfuzor compile filesystem intent before applying it, and
> what execution mechanism should consume the resulting specification?

In the newer pipeline vocabulary, the target shape is:

```text
raw -> norm -> spec -> optional synthesis -> apply
```

Applied to filesystem artifacts:

| Stage | Responsibility | Effect |
|---|---|---|
| `raw_fs` | Public `FILES`, `*_FILES`, `*_DIRS`, properties, and bypass inputs | none |
| `norm_fs` | Normalize scalar/list/mapping forms and identify writer kinds | none |
| `spec_fs` | Resolve hierarchy roots, destinations, provenance, policy, and writer inputs | none |
| `_syn_fs` | Optional backend-specific grouping, bundles, scripts, or transfer plans | none |
| `fs_apply` | Consume explicit records and alter the host | host filesystem |

The current `_ARTIFACTS` is an early `spec_fs`, although its name and shape are
not yet committed as public architecture. It still reaches back into raw
declarations during apply.

## Shared constraints

Every option should preserve these unless it explicitly argues otherwise.

### Path semantics

- Preserve the `defaultDir` pattern.
- Relative destinations receive their compiled family root.
- `/` and `~` destinations stand on their own.
- `.` and `..` remain valid trusted playbook input.
- `FS_CONTAINERED` retains distinct materialized and exposure roots.
- Structural hierarchy links remain distinct from deferred activation LINKS.

### Artifact semantics

The pipeline must account for at least:

- template source files;
- raw file copies;
- generated `content`, `yaml`, `json`, and variable content;
- directory copies;
- line edits with regexp/create/state controls;
- declared directories;
- `once` behavior;
- backup behavior;
- mode, owner, and group inheritance;
- family and global bypasses;
- privilege calculation;
- check mode and useful diffs;
- source and destination errors;
- provenance in diagnostics.

### Performance

The design should distinguish several different costs:

1. **Compile cost:** Jinja rendering, lookups, filters, normalization.
2. **Controller orchestration:** includes, task expansion, loop preparation,
   serialization, callback output.
3. **Transport cost:** module packaging and remote round trips. Local connector
   runs still pay module startup and serialization costs.
4. **Target work:** filesystem probes, reads, writes, metadata changes, hashes.

Reducing task-file count does not necessarily reduce module invocations. A
single Ansible task looping over 100 files still invokes the module for every
item. Any performance claim must say which cost it reduces.

### Correctness and observability

- Compilation should reject malformed declarations before host mutation.
- Apply should consume explicit records rather than reinterpret public vars.
- Check mode should predict changes without applying them.
- Diffs should remain useful for text artifacts.
- Failures should identify artifact origin and resolved destination.
- Partial application behavior should be deliberate and documented.
- A backend must not silently implement different ownership or bypass semantics.

## Evaluation fixture

Before selecting an option, build one repeatable fixture with a representative
mix:

- generic `FILES` and at least four fsh families;
- containered and non-containered layouts;
- family roots, hierarchy exposure links, and subdirectories;
- template, raw copy, generated JSON, generated text, directory copy, and line
  edit records;
- mixed ownership and privilege requirements;
- unchanged, changed, absent, conflicting, and `once` destinations;
- enough records to expose orchestration overhead rather than noise.

For each candidate measure:

- playbook wall time over cold and warm runs;
- number of expanded tasks;
- number of target module/process invocations;
- controller CPU time;
- target CPU and bytes read/written where practical;
- check-mode accuracy;
- diff quality;
- idempotent second-run behavior;
- failure locality after injecting one invalid or unwritable record;
- implementation size and number of duplicated semantic rules.

The fixture should record behavior as well as speed. A backend that is fast
because it stops producing useful diffs or silently ignores ownership is not an
equivalent implementation.

# Option A: Keep family executors, deepen the compiled spec

## Shape

```text
raw families
  -> compile complete artifact and family specs
  -> _multi
  -> fs_hierarchy per active family
  -> existing Ansible modules
```

This is the smallest continuation from the current state. Keep `_multi.tasks`,
`fs_base.tasks`, and family-oriented `fs_hierarchy.tasks`, but make them thinner.
Move remaining interpretation into compilation:

- normalize `<KIND>_DIRS` into family directory records;
- compile family root/link properties and bypass state;
- compile copy source kind and source path;
- compile generated-content kind;
- compile mode/owner/group/backup/once fields;
- publish explicit copy and line records per family;
- leave apply tasks responsible only for Ansible module arguments and
  `become_calc` where host identity is required.

The family executor becomes an adapter over one family spec instead of a second
interpreter.

## Advantages

- Lowest behavioral risk.
- Existing family-level debugging remains recognizable.
- Easy to migrate one semantic field at a time.
- Ansible's copy, template, lineinfile, check-mode, diff, ownership, and backup
  behavior remain available.
- Family bypass and family property concepts remain naturally grouped.
- Good intermediate step even if another backend is eventually selected.
- Deepens `spec_fs` without prematurely binding it to a flat or batch backend.

## Dangers and limitations

- `_multi` variable-name discovery remains architecture rather than migration
  scaffolding.
- Dynamic includes and family-local `set_fact` continue to add orchestration
  overhead.
- Root/link probing remains repeated per family.
- Generic `FILES` remains structurally exceptional unless forced through a
  synthetic family.
- A deep spec plus a family adapter can become two abstractions where one would
  suffice.
- Performance improvement may be modest because module invocation count is
  unchanged.
- The easiest migration path can become permanent before the desired final
  shape is reconsidered.

## Evidence that would justify it

- Compilation consistency matters more than current runtime cost.
- Benchmarking shows module execution dominates include/task overhead.
- Family-specific behavior remains extensive enough that flattening would add
  branching rather than remove it.
- A staged migration is desired before choosing a more aggressive backend.

## Exit criteria

- No apply task reads destination, source kind, mode inheritance, or annotation
  meaning from a raw declaration.
- Family executors consume only compiled records.
- Raw artifact variables are not referenced after the compile boundary.

# Option B: Flatten into a small set of Ansible apply loops

## Shape

```text
raw families
  -> compile complete spec_fs
       family_roots[]
       hierarchy_links[]
       directories[]
       copies[]
       lines[]
  -> fs_apply.tasks
       file roots loop
       structural links loop
       directories loop
       copy loop
       lineinfile loop
```

This completes the direction anticipated by `_ARTIFACTS.copies` and
`_ARTIFACTS.lines`. Remove `_multi` from filesystem apply. One static task file
consumes backend-neutral flat collections.

Each record carries family context so diagnostics and inherited properties are
not lost merely because execution is flat.

## Advantages

- Clear `spec_fs -> fs_apply` handoff.
- Removes dynamic variable-name discovery from apply.
- Removes one include and one setup fact per active family.
- Makes generic `FILES` an ordinary family/root case rather than a parallel
  executor.
- Centralizes writer tasks and exposes duplicated behavior immediately.
- Easier to reason about total ordering across families.
- Easier to test that every compiled record reaches exactly one writer.
- Retains standard Ansible modules and their check/diff semantics.
- Likely best balance of architecture improvement and implementation risk.

## Dangers and limitations

- Module invocation count remains one per loop item.
- Large loop output can still be expensive and noisy.
- Family-specific defaults must be fully compiled; hidden dependence on
  task-local family vars will cause regressions.
- Ordering changes from “complete one family, then the next” to “all roots,
  then all dirs, then all copies, then all lines.” Some undeclared dependency
  may rely on old family ordering.
- `lineinfile` after copies is globally clear but may differ from current
  per-family order.
- Flat records can become wide bags of optional fields if writer-specific
  schemas are not separated.
- Privilege may vary by record, so each loop still evaluates become metadata.

## Design choices internal to this option

Two orderings deserve explicit comparison:

1. **Writer-major:** all roots, links, dirs, copies, lines.
2. **Dependency-major:** roots and dirs globally, then ordered artifact records
   where each record selects its writer.

Writer-major maps cleanly to Ansible tasks. Dependency-major preserves authored
ordering better but requires dynamic dispatch or grouped include behavior.

## Evidence that would justify it

- Includes, setup facts, variable-name queries, and task templating are a
  measurable part of runtime.
- Family ordering has no intentional semantic role after roots are established.
- Standard module behavior is still valuable enough to reject a custom batch
  implementation.

## Exit criteria

- `_multi.tasks` is not part of filesystem apply.
- `fs_base.tasks` and `fs_hierarchy.tasks` are replaced by one spec consumer.
- Writer records use distinct validated schemas rather than arbitrary raw maps.
- Integration tests prove ordering for generated files plus line edits.

# Option C: Custom action plugin over standard modules

## Shape

```text
spec_fs
  -> compfuzor filesystem action plugin
       validate/order/group on controller
       invoke standard Ansible modules for groups or records
```

An action plugin receives the complete filesystem specification in one authored
task. Controller-side Python owns ordering, temporary data, diagnostics, and
module invocation. Target effects can still delegate to `file`, `copy`, and
line editing modules rather than reimplementing all filesystem behavior.

## Advantages

- One visible playbook task and one stable input contract.
- Removes most Jinja and task-file orchestration from filesystem application.
- Controller code can group records, preflight the whole plan, and produce
  better provenance-aware errors.
- Can retain selected standard-module semantics by invoking those modules.
- Provides a migration path between flat Ansible loops and a true batch module.
- Could centralize check-mode ordering and partial-failure policy.

## Dangers and limitations

- An action plugin does not automatically reduce target module invocations; if
  it invokes one module per artifact, transport/process costs remain.
- Programmatic module invocation is less transparent than ordinary YAML tasks.
- Callback output and diffs may be harder to integrate naturally.
- Action-plugin APIs are more coupled to Ansible internals than filter plugins
  and ordinary task files.
- Debugging controller/target boundaries becomes specialized knowledge.
- It risks becoming an orchestration framework inside Ansible without gaining
  the performance of real batching.
- Error recovery after several delegated module calls needs explicit design.

## Evidence that would justify it

- Controller task expansion is expensive, but standard target modules remain
  important.
- A prototype demonstrates materially lower controller overhead without losing
  check-mode or diff quality.
- The action plugin can expose per-record results clearly enough for ordinary
  debugging.

## Exit criteria

- The plugin input is the same backend-neutral `spec_fs` used by tests.
- Module delegation behavior is tested against equivalent ordinary tasks.
- It demonstrates a concrete advantage over Option B, not merely fewer lines of
  YAML.

# Option D: Custom target-side batch module

## Shape

```text
spec_fs
  -> one compfuzor_fs Ansible module invocation
       preflight all records
       inspect target once
       apply ordered changes
       return per-record result and diff data
```

This is the strongest direct attack on Ansible overhead. Serialize the compiled
filesystem specification once, execute one target-side Python process, and
apply the complete plan there.

The module would need implementations for directory creation, structural
symlinks, regular-file writes, metadata, backups, once policy, and line edits.
Template rendering could remain controller-side and send final bytes, or the
module could receive staged source files.

## Advantages

- One module transfer/startup and one controller-to-target round trip.
- Target can preflight the complete plan before mutation.
- Shared filesystem probes and parent calculations can be deduplicated.
- Easy to provide deterministic ordering and structured per-record results.
- Can implement atomic temporary-write-plus-rename for regular files.
- Can avoid rereading the same directories and metadata across records.
- Best candidate when module startup and transport dominate runtime.

## Dangers and limitations

- Reimplements mature Ansible behavior.
- Check mode, text/binary diffs, vault/no-log handling, backups, SELinux,
  attributes, ownership, modes, symlink following, and platform differences all
  become compfuzor responsibilities.
- Line editing is deceptively complex; faithfully matching lineinfile behavior
  is a project of its own.
- Shipping generated bytes or source files into one module requires careful
  payload and temporary-file design.
- Large content may exceed comfortable module argument sizes.
- One process creates a larger failure domain. Without transactional design,
  failure halfway through still yields partial state.
- Transactional rollback across ownership, links, directories, and arbitrary
  line edits is much harder than atomic file replacement.
- Specialized code has a larger security and maintenance surface.

## Variants

- **D1: metadata-only batch module.** Roots, directories, and links are batched;
  standard copy/line modules remain.
- **D2: immutable-file batch module.** Directories and final file bytes are
  batched; line edits remain standard Ansible.
- **D3: complete module.** Every filesystem artifact goes through one backend.

D1 and D2 can test the performance premise without committing to line-edit
reimplementation.

## Evidence that would justify it

- Benchmarks show module startup/transport dominates compile and controller
  overhead.
- Deployments routinely carry enough artifacts for batching to matter.
- A narrow D1/D2 prototype preserves check-mode and reporting quality.
- Supported target platforms have a reliable Python runtime compatible with the
  module.

## Exit criteria

- Differential tests compare module results with standard Ansible modules.
- Check mode is accurate for every supported record type.
- Per-record failures identify origin and leave documented partial state.
- Special files, symlinks, permissions, and unsafe replacement cases have
  explicit tests.

# Option E: Render a staging tree, then synchronize

## Shape

```text
artifact specs
  -> controller or deployment staging tree
  -> rsync/synchronize/copy-tree into materialized roots
  -> separate structural links and mutable edits
```

Generated and source-backed files are first assembled into one tree matching
their destination-relative layout. A synchronization mechanism transfers each
tree or family in bulk. Mutable operations such as line edits remain separate.

## Advantages

- Bulk transfer can be much faster than one copy module invocation per file.
- Staging output is directly inspectable and testable.
- Tree diffs and package-like artifacts become possible.
- Naturally supports manifests, checksums, and reproducible bundles.
- Immutable generated content can be separated cleanly from mutable host edits.
- Rsync already handles incremental transfer, modes, directories, and deletion
  policies efficiently.
- Could support offline inspection before applying.

## Dangers and limitations

- Destination roots are not always one owned tree; absolute destinations can
  escape family roots.
- Synchronization deletion semantics are dangerous around user/operator files.
- Mixed owners, groups, and privilege requirements complicate one bulk pass.
- `~`, `..`, and cross-root destinations weaken simple tree mapping.
- Line edits and `once` files do not fit immutable synchronization.
- Controller-side staging can mishandle templates that rely on target facts or
  target-side files.
- Remote hosts require transfer and staging-space lifecycle decisions.
- Check-mode and per-file Ansible diffs may degrade into rsync summaries.
- SELinux labels and uncommon filesystem metadata need separate handling.

## Variants

- **E1: one tree per artifact family.** Simple roots, more synchronization
  invocations.
- **E2: one deployment tree under `DIR`.** Best for `FS_CONTAINERED`; external
  exposure remains links or install-time synchronization.
- **E3: content-addressed staging.** Store immutable objects once and assemble
  destination trees through links/reflinks/copies.

## Evidence that would justify it

- Most artifacts are immutable generated/copied files under owned roots.
- Copy module invocations dominate runtime.
- Mixed ownership and absolute escape destinations are rare enough for a
  fallback backend.
- Operators value inspectable/reproducible trees more than per-file Ansible
  output.

## Exit criteria

- Synchronization never deletes unowned files by default.
- Ownership boundaries and fallback records are explicit in `spec_fs`.
- Mutable records are excluded rather than approximately translated.
- Check-mode output identifies the files that would change.

# Option F: Generate a filesystem bundle and apply it later

## Shape

```text
compile/render during playbook
  -> DIR/fs-plan.json + staged payloads or archive
  -> generated install-filesystem[-user] tool
  -> apply/status/remove at activation time
```

This extends the record-then-apply model used by deferred LINKS to filesystem
artifacts themselves. Ansible produces the deployment bundle but does not
materialize selected external files immediately. A runtime manager applies
them in system or user scope.

This is not equivalent to staging plus sync: the durable plan and lifecycle
manager are the primary contract, and status/removal can consume the same
record.

## Advantages

- Clean deploy/activate split for user filesystem surfaces.
- Durable desired-state record enables status and conservative removal.
- One rendered deployment can activate for multiple users when paths retain
  runtime roots.
- External filesystem mutation becomes explicit and manually invokable.
- Supports offline review and potentially signed bundles.
- Could unify file and link ownership reporting.
- Avoids running user-scope writes as the deployment actor.

## Dangers and limitations

- Many files are inputs to later tasks in the same playbook and cannot be
  deferred safely.
- Generated scripts and env files may depend on files existing before BINS are
  rendered or run.
- Runtime application needs privilege, ownership, backup, conflict, and removal
  policy substantially richer than LINKS.
- User override semantics for file content are harder than symlink
  don't-stomp semantics.
- Secrets and sensitive generated content would persist in bundles.
- Line edits cannot be safely reversed from desired-state data alone.
- This can duplicate configuration-management behavior inside compfuzor.
- Scope mistakes become activation-time failures rather than deploy-time
  failures.

## Evidence that would justify it

- There are concrete multi-user or delayed-activation file consumers beyond
  symlinks and env.
- Most candidate files are not required during the generation play.
- Status/removal value outweighs the added runtime policy system.
- A narrow user-surface prototype demonstrates clear operational improvement.

## Exit criteria

- Deferred eligibility is explicit per record; it is never inferred merely from
  destination shape.
- Generation dependencies prevent required files from being deferred.
- Secrets and user overrides have explicit policies.
- Apply/status/remove agree on ownership from one plan.

# Option G: Hybrid backends selected by artifact semantics

## Shape

```text
one spec_fs
  -> backend selection during synthesis
       structural roots/links -> standard Ansible file tasks
       immutable trees        -> staging + sync or batch copy
       mutable line edits      -> lineinfile
       unusual records         -> ordinary per-record copy
       deferred user surfaces  -> runtime bundle
```

This treats backend selection as a synthesis concern. The artifact compiler
describes meaning; `_syn_fs` selects an execution backend based on explicit
capabilities and policy.

Unlike accidental fallback logic, every record carries or derives a declared
backend class, and every backend implements a documented subset.

## Advantages

- Optimizes common immutable cases without forcing all semantics into one
  custom implementation.
- Preserves mature standard modules for difficult mutable cases.
- Allows incremental experiments behind one `spec_fs` contract.
- Gives `FS_CONTAINERED` deployments a natural staging-tree fast path.
- A batch module can start narrow and grow only when evidence supports it.
- Backend-specific limitations become validation errors before apply.
- Most plausible route to both performance and semantic coverage.

## Dangers and limitations

- Highest architectural complexity.
- Backend selection can become a policy maze.
- Equivalent records may behave differently if capability detection changes.
- Ordering and dependencies across backends require an explicit graph or fixed
  barriers.
- Check-mode and reporting must aggregate heterogeneous result shapes.
- Ownership and conflict semantics can drift between implementations.
- Testing expands combinatorially across artifact kind, backend, scope, and
  containered mode.
- A hybrid can preserve every old special case instead of simplifying the
  model.

## Required guardrails

- One canonical artifact schema independent of backend.
- One shared ownership, bypass, and replacement vocabulary.
- Explicit backend capability declarations.
- Deterministic selection recorded in `_syn_fs` for inspection.
- A universal standard-Ansible fallback.
- Cross-backend ordering barriers defined as data.
- Differential conformance tests for semantics shared by multiple backends.

## Evidence that would justify it

- Benchmarks show different record classes have different dominant costs.
- No single backend offers acceptable semantics and performance.
- `spec_fs` is stable enough that backend experimentation does not perturb
  authoring APIs.
- The team is willing to maintain conformance tests as a first-class subsystem.

## Exit criteria

- Backend choice is visible and explainable for every record.
- Adding a backend does not change public `FILES` authoring syntax.
- Cross-backend ordering and partial failure are tested.
- At least one optimized backend demonstrates a measured win over Option B.

## Cross-option decisions

These decisions are required regardless of which execution option advances.

### How deep is `spec_fs`?

The current record carries `resolved_dest` plus the raw declaration. A deeper
spec could carry:

```yaml
id: ETC_FILES:watchman.json
origin: { family: ETC_FILES, index: 0, subsystem: watchman }
kind: etc
writer: generated-json
dest: /etc/opt/watchman-main/watchman.json
source: { json: { ... } }
mode: "0660"
owner: watchman
group: watchman
backup: false
once: false
bypass: false
```

The more complete the spec, the easier it is to support multiple backends. The
danger is compiling values too early when they depend on task-local templating,
target facts, or privilege probes.

### Where are bytes rendered?

Possible boundaries:

- retain Ansible template lookup inside apply;
- render final bytes during compilation on the controller;
- render into a staging tree during synthesis;
- send templates and context to a target-side backend.

Rendering final bytes early simplifies apply and hashing, but it may expose
secrets in facts and callback output. Carrying template intent preserves late
binding but keeps apply coupled to raw authoring semantics.

### Is authored ordering semantic?

Current behavior is family-major and writer operations are interleaved within a
family. Flattened and batch designs prefer dependency barriers. We need to know
whether any playbooks intentionally rely on:

- one family being fully complete before another begins;
- a line edit following a copied file in the same declaration list;
- one artifact creating a source consumed by a later artifact;
- filesystem artifacts existing before BINS rendering or execution.

If ordering is semantic, encode dependencies or phases. Do not preserve an
accidental list order indefinitely without naming its contract.

### What is owned?

Directories, copied files, edited files, structural links, and deferred links
have different reversal properties. A future filesystem plan should distinguish:

- fully managed content;
- managed-if-absent (`once`);
- mutable host content with a managed line/block;
- structural deployment topology;
- user/operator overrides;
- externally owned parents.

Ownership vocabulary is needed even if uninstall remains out of scope, because
it determines replacement, drift, and synchronization deletion safety.

### How are privilege decisions represented?

`become_calc` currently runs close to each effect. Compiling a boolean too early
can freeze the deployment actor's context into a reusable spec. Alternatives:

- compile desired owner/group but calculate become at apply;
- group records by privilege context during synthesis;
- let a target-side module inspect current identity and paths;
- require system/user scopes as explicit privilege domains.

The design should compile intent, not accidentally persist a transient answer
to “can this actor write here?”

## Comparative summary

| Option | Primary win | Main danger | Standard module semantics | Likely module invocation reduction |
|---|---|---|---|---|
| A. Deeper family adapters | consistency, low risk | migration layer becomes permanent | high | none |
| B. Flat Ansible loops | clean pipeline, less orchestration | hidden ordering/family assumptions | high | none |
| C. Action plugin | controller orchestration | Ansible-internal complexity without target savings | medium-high | none unless grouped |
| D. Batch module | transport/process performance | reimplementing Ansible filesystem semantics | low unless rebuilt | high |
| E. Staging + sync | bulk immutable transfer | deletion/ownership and mutable records | medium | high for eligible trees |
| F. Deferred bundle | deploy/activate lifecycle | duplicates configuration management | custom | high during generation; moves work later |
| G. Hybrid backends | optimize by semantics | complexity and semantic drift | mixed | class-dependent |

## Provisional reading, not a decision

Option B is the clearest completion of the architecture already started. It
turns `_ARTIFACTS` into a real apply interface while retaining standard Ansible
behavior. Its likely performance improvement is bounded because loop items still
become module invocations.

Option A is a useful migration tactic if Option B exposes too many hidden family
dependencies. It is less compelling as a destination.

Options D and E are the serious performance options. They should be justified
by measurement, and both are safer when attempted for a narrow immutable subset
before expanding.

Option C needs proof that controller orchestration alone is the problem; it can
otherwise add specialized machinery without reducing target work.

Option F is architecturally coherent with deferred LINKS but should be driven by
a concrete activation need, not symmetry for its own sake.

Option G is the most flexible long-term possibility and the easiest to
overdesign. It becomes reasonable only after one stable `spec_fs` and benchmark
evidence show that no single backend fits.

No implementation should begin from this provisional reading alone. The next
useful work is the evaluation fixture and a sharper inventory of existing
artifact semantics and ordering dependencies.

## Suggested future waves

1. **Inventory0:** classify in-tree filesystem declarations by writer, family,
   ownership, ordering, privilege, and mutability. Identify declarations that
   do not fit the current compiled schema.
2. **Bench0:** establish the representative fixture and measure the current
   family executor.
3. **Flat0:** prototype Option B without changing public authoring syntax and
   compare behavior/task counts.
4. **Batch0:** only if measurement warrants it, prototype D1 or D2 against the
   same fixture.
5. **Synthesis:** compare measured results and choose whether the project needs
   a single backend or an explicit hybrid.

## Cross-references

- [`/.design/link-script/draft2-0.gpt56.md`](/.design/link-script/draft2-0.gpt56.md)
  introduced compiled artifact destinations and explicitly left family-oriented
  execution as an acceptable first implementation.
- [`/library/filter_plugins/artifact_links.py`](/library/filter_plugins/artifact_links.py)
  contains the current proto-`spec_fs`: family roots, resolved destinations,
  provenance, and flat copy/line collections.
- [`/tasks/compfuzor/compile_artifacts.tasks`](/tasks/compfuzor/compile_artifacts.tasks)
  shows the current explicit collection of public artifact-family inputs.
- [`/tasks/compfuzor/fs_hierarchy.tasks`](/tasks/compfuzor/fs_hierarchy.tasks)
  is the family-oriented executor whose remaining responsibilities define much
  of the migration surface.
- [`/tasks/compfuzor/fs_base.tasks`](/tasks/compfuzor/fs_base.tasks) is the
  separate generic FILES executor that a flat pipeline could absorb.
- [`/tasks/compfuzor/_multi.tasks`](/tasks/compfuzor/_multi.tasks) performs the
  variable-name discovery and family fanout retained by Options A and removed
  by Option B.
- [`/doc/pipeline-and-intent-prefix-memo.md`](/doc/pipeline-and-intent-prefix-memo.md)
  defines the `raw -> norm -> spec -> syn -> apply` lifecycle used to compare
  these options.
- [`/doc/prefix-review.md`](/doc/prefix-review.md) identifies hierarchy and
  `_multi` fanout as a significant gap in the newer pipeline architecture.
