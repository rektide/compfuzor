---
type: ArchitecturalAssessment
title: Core re-scope for contexts, commands, and complete installs
description: Separate Compfuzor's reusable context and invocation concerns from Zim's domain-specific activation lifecycle without inventing a universal install framework.
resource: /.design/config-user-target/core-rescope0.unknown.md
tags: [compfuzor, config, contexts, bins, install, zim, architecture]
status: draft
generated: { by: model:unknown, at: 2026-09-11 }
verified: { by: unverified }
stale_after: 2026-10-11
sources:
  - id: current-index
    resource: /.design/config-user-target/README.md
    title: Consumer config current implementation and design history
  - id: prior-assessment
    resource: /.design/config-user-target/assessment0.unknown.md
    title: Reusable configuration tools, explicit consumer contexts
  - id: build5
    resource: /.design/config-user-target/build5.solx.md
    title: Context-aware Zim installation surface
  - id: build5-review
    resource: /.design/config-user-target/build5-review0.solx.md
    title: Build 5 context semantics review
  - id: operator-guide
    resource: /doc/config/consumer-toolkit.md
    title: Consumer configuration toolkit
---

# Core re-scope for contexts, commands, and complete installs

The exact underlying model identifier is not exposed in this session; the
`unknown` suffix and `model:unknown` author label are intentional. This is an
independent source assessment. It does not authorize implementation or replace
the parent agent's architectural judgment.

## Executive verdict

The concern is valid, but the implementation has not simply turned core design
problems into Zim features.

**`ZIM_CONTEXTS` is mostly a healthy, shallow domain adapter over substantive
general modules.** Its two loader channels, two cache builds, controller,
emergency behavior, registry, and producer format are genuinely Zim-specific.
Deleting that adapter leaves a coherent generic CONFIGS context toolkit and a
coherent LINKS manager.

Zim has, however, exposed two missing core concepts:

1. **A selected invocation**: one real command chooses a declared context using
   explicit CLI, an optional user-created `$0` symlink, environment, then a
   compiled default.
2. **A composed invocation**: BINS should be able to compose a command plus
   arguments/default profile, rather than requiring every composed operation to
   be represented by another filename.

Those are narrower than a generic install-plan engine. Config and Zim can be
the two real consumers that justify extracting them. Zim is currently the only
real consumer of a multi-step, complete context install, so that orchestration
should remain Zim code.

The simplest model is:

```text
declaration -> context binding -> domain action -> shared effects
                    ^                  ^
          where/for whom          what must happen

BINS composes an ordinary invocation and orders it; it does not implement it.
```

- A **context** answers where and for which consumer.
- A domain **action** answers what operation is being requested.
- A **strategy** answers how one bounded effect is represented.
- **BINS** answers which ordinary invocations belong in an aggregate action and
  in what order.

This keeps the useful Build 1–5 behavior while moving default/context/alias
selection and command composition to the level where they actually recur.

## 1. What is general today, and what is Zim

The useful unit of inventory is a contract or executable responsibility, not a
line count.

### General mechanisms already present

| General area | Current contract | Useful size |
|---|---|---|
| CONFIGS recipe compiler | [`config_compile.py`](/library/filter_plugins/config_compile.py) compiles reusable inputs, outputs, validation, and processor identity. [`config-run.sh`](/files/config-run.sh) privately builds candidates, validates them, and atomically commits selected outputs. | One durable spec; three processor kinds (`concat`, `json-deep-merge`, `block-in-file`); one transaction runner. |
| Consumer context binding | [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py) overlays named user/system roots and per-recipe input/output selectors. [`config/context.ts`](/files/config/context.ts) resolves selectors and binds a recipe for the invoking environment. | One context schema and path-selector vocabulary; two scope classes; one binding module. |
| Consumer config operations | [`config/toolkit.ts`](/files/config/toolkit.ts) owns ordinary install, input synchronization, whole-output publication, local input mutation, and multi-representation status. [`config-context.ts`](/files/config-context.ts) invokes the unchanged CONFIGS runner against a temporary bound spec. | Five top-level toolkit actions (`install`, `dropins`, `whole`, `inputs`, `status`), with six input subactions; one shared implementation. |
| Generated context command surface | The context compiler materializes `config-<context>`, ordinary install, three drop-in variants, two whole-output variants, input operations, and status. | **Nine wrapper files per context**, regardless of declared policy. It also deploys exactly four shared implementation records: `config-context.ts`, `config/context.ts`, `config/toolkit.ts`, and `links/delivery.ts`. |
| Safe file delivery | [`links/delivery.ts`](/files/links/delivery.ts) provides entry inspection, physical-alias checks, and atomic copy/link replacement without replacing directories or special files. | One import-safe effect module, already used by CONFIGS and LINKS. |
| Managed links | [`links/links.ts`](/files/links/links.ts) owns durable link-plan apply/status/audit/remove, collision policy, runtime-root resolution, and privilege routing. | One versioned manifest and four actions. Its ownership policy remains distinct from receipt-free CONFIGS delivery. |
| Runtime packaging | [`runtime_bundles.py`](/library/filter_plugins/runtime_bundles.py) emits the delivery-only or full LINKS module bundle without copying source logic. | One small packaging helper; not an operation framework. |
| Action composition | [`bin_composers.py`](/library/filter_plugins/bin_composers.py) discovers filename-shaped build/install/apply leaves, groups by scope and subsystem, and orders them by lanes. [`files/_bin`](/files/_bin) renders wrappers and `run_all`. | Three recognized actions, two composition tiers, five scheduling lanes, and one string-only child invocation form. |
| Named-block observation | [`block-status.sh`](/files/block-status.sh) compares one declared source with one named managed block. Mise uses it directly. | One small observation primitive; no assembly model. |

Only `zim.opt.pb` currently declares `CONFIG_CONTEXTS` in a checked-in product
playbook. The generic two-context behavior is nevertheless exercised directly
by the config integration fixtures; it is not implemented inside Zim. This is a
real generic implementation with one current checked-in domain adopter, not a
fleet of independently proven domain adapters.

### Zim-specific adapter and behavior

| Zim area | Current contract | Useful size |
|---|---|---|
| Activation compilation | [`zim_context_compile.py`](/library/filter_plugins/zim_context_compile.py) requires `zimrc` and `zimenv`, references a CONFIG context, derives scope, and compiles activation paths plus canonical Zim inputs. | One versioned Zim spec. Each activation adds one config-context reference and four Zim destinations. The canonical section has ten explicit Zim inputs/identities. |
| Complete lifecycle | [`zim/install.ts`](/files/zim/install.ts) resolves settings, asks the config toolkit to install, projects two loaders, installs two named blocks, builds two caches, applies one registry link, imports producers, and reports activation status. | One runtime, three actions (`install`, `import`, `status`), exactly two channels. |
| Host commands | The Zim compiler emits `install-zim.sh`, `status-zim.sh`, and the internal `zim/install.ts`; [`gen_zim.tasks`](/tasks/compfuzor/gen_zim.tasks) separately contributes donor and context-import roles. | Three activation records plus two explicit host-role commands. No generated context aliases. |
| Contributor command | Contributors receive scope-neutral `install-zimfw.sh`, composed into their user lane by metadata. | One generated role command per contributor; it imports producer fragments rather than installing the host. |
| Loader content | `zim.opt.pb` owns the two fixed templates and their placeholders. | `.zshenv`/`zimenv` and `.zshrc`/`zimrc`, with intentionally different shell semantics. |
| Producer protocol | Contributor fragments use `etc/zim/<channel>/{active,disabled}`; donor promotion and consumer import are separate. | One Zim package-exchange convention, not a generic config input protocol. |

The current Zim host therefore has **one complete install command, one Zim
status command, and two explicit administrative/import role commands**. Its
large visible config surface comes from the generic compiler's nine files for
the one `user` config context, not from Zim aliases.

## 2. Deletion tests and the adapter boundary

### Delete Zim

If `ZIM_CONTEXTS`, `zim_context_compile.py`, `zim/install.ts`, the loader
templates, and the Zim role commands disappear:

- CONFIGS can still compile and assemble arbitrary recipes;
- CONFIG_CONTEXTS can still bind multiple runtime consumers;
- the toolkit can still seed/refresh inputs, assemble locally, publish copies or
  links, mutate local inputs, and classify status;
- LINKS and BINS remain independently coherent.

That is a passing deletion test for a domain adapter.

### Delete the generic context/toolkit layer but keep Zim

Zim would have to reimplement path-selector expansion, consumer input binding,
seed-versus-refresh behavior, local assembly, whole copy/link delivery,
physical-alias protection, and matching-representation status. That is evidence
of a real deep core below Zim.

### Delete `ZIM_CONTEXTS` but retain multiple Zim activations

The generic config context still cannot express:

- the startup-file root;
- independent `zimrc` and `zimenv` cache homes;
- the registry destination;
- the fixed loader projection and legacy normalization;
- the Zim controller/emergency module;
- producer inventory and per-channel cache rebuilds.

Putting these fields into `CONFIG_CONTEXTS` would make config less deep by
turning it into an assortment of application hooks. A Zim adapter is warranted.

### Exact field ownership

These should remain Zim concepts:

- activation fields `config`, `loader_root`, `zimrc_home`, `zimenv_home`, and
  `registry`;
- canonical `zimrc`, `zimenv`, their legacy lists and loader templates,
  `controller`, `emergencyModule`, registry source, and block prefix;
- the two channel names and their different loader semantics;
- loader projection/quoting and legacy block removal;
- cache construction and freshness rules;
- producer directory conventions, donor promotion, contributor host discovery,
  and selective touched-channel rebuild;
- the sequence defining a complete Zim install and Zim activation status.

The activation's `scope` should remain derived from the referenced core context,
not become a second authored choice. Carrying it in a compiled Zim spec as an
integrity check is reasonable; duplicating its authority is not.

These are core candidates:

- path-selector syntax and expansion;
- declared-name validation and lazy precedence resolution;
- compiled default-context metadata;
- an explicit BINS composition invocation independent of executable filename;
- delivery entry inspection and atomic copy/link effects, which are already
  shared.

### “One adapter hypothetical, two adapters real”

Apply the rule seam by seam:

| Proposed seam | Real consumers now | Judgment |
|---|---|---|
| Atomic copy/link and entry inspection | CONFIG toolkit + LINKS | Already justified and correctly extracted. |
| Path selectors used by activation paths | CONFIG binding + Zim activation | Justified. Make the compile helper public rather than importing a private symbol. Do not force LINKS' different runtime-root contract into it yet. |
| Full context/default/CLI/env/`$0` resolution | Zim only today; a consolidated generic config command would be the second | Extract while introducing that second real consumer, not as a speculative framework beforehand. |
| Complete multi-step context install plan | Zim only | Keep domain-local. Systemd is a comparison candidate, not proof that its semantics match. |
| Universal status row/ontology | CONFIG, LINKS, Zim, Mise all observe different relationships | Share exit/reporting adapters only where exact contracts coincide; do not erase the domain distinctions. |

Thus `ZIM_CONTEXTS` is healthy in content but diagnostically useful: it shows
that invocation selection and BINS invocation composition are too shallow in
core.

## 3. Where invocation resolution should live

It should not live in `bin_composers.py`. BINS runs at compile time and should
not read the eventual caller's environment or `$0`. It also should not live in
path binding: selecting a named context precedes resolving paths inside it.

Use a small import-safe **invocation-selection module** adjacent to runtime
context code. It should resolve one declared name from caller-supplied inputs:

```text
explicit CLI
  > valid context inferred from the unresolved invoked basename
  > domain runtime environment
  > domain compiled default
```

Required semantics:

1. Capture the invoked basename before resolving the symlink.
2. If CLI context is explicit, do not parse or validate `$0` at all. This lazy
   behavior is important: explicit intent must escape a stale or oddly named
   symlink.
3. `$0` may infer only a context, never an action or strategy.
4. Validate the final name against the domain's declared context map.
5. Let each domain supply its environment variable and alias grammar. A common
   resolver should not hard-code `ZIM` or CONFIG vocabulary.
6. Resolve only settings needed by the selected action. Status should not fail
   because an unrelated install-strategy environment variable is malformed.

The module is a selection function, not an action dispatcher, plugin registry,
or generic CLI parser. Config and Zim should remain responsible for parsing
their own actions and domain options.

The current implementation duplicates only part of the policy:

- Zim has the full precedence in `resolveSettings` and `aliasContext`;
- config wrappers bake `--context`, while toolkit strategy selection handles
  environment then context defaults but has no domain default or `$0` context;
- `config-context.ts` requires `--context` and does no default selection.

The extraction becomes real when a single generic config command also uses it.
Before that point, leave it local to the first migrated command rather than
designing a broad invocation-profile schema.

## 4. Complete installation, composition, and lifecycle words

### Where complete install belongs

“Complete install for this context” belongs in the **domain action**. For Zim,
that is `zim/install.ts`: config preparation, loader installation, cache builds,
and registry exposure form one user-recognizable operation with Zim-specific
ordering and failure behavior.

BINS should know only that the ordinary Zim install invocation participates in
an aggregate `install` action, its default scope lane, subsystem, and ordering
lane. It should not know the two channels or encode their steps.

### Should install plans become data?

Not yet. BINS records are already enough plan data for independent command
composition. The missing data is a **structured invocation**—command plus fixed
subcommand/arguments and composition metadata—not a graph of internal effects.

A conceptual composition record is sufficient:

```yaml
command: config-context.sh
compose_as:
  action: install
  scope: user
  args: [install]
```

The exact schema is a later checkpoint. The important separation is that the
record creates no `install-config-user.sh` file. It tells an aggregate
compositor how to invoke the one real command.

A generic install-step plan would immediately need answers about rollback,
conditional steps, outputs passed between steps, retries, privilege, status,
and partial failure. Zim, systemd, Rust, and package managers do not currently
share those answers. Encoding the Zim sequence as generic data would move code
without deepening an interface.

### Compile-time scope versus runtime context

Today `install-zim.sh` joins the lane matching the compiled default context, but
the same command can select another scoped context at runtime. This is not an
implementation copy, and scope never implies sudo. It is nevertheless a
semantic tension:

- `scope` in BINS describes ordinary composition membership;
- `scope` in a context classifies its root defaults and expected execution
  environment;
- neither is a runtime security boundary.

The least surprising contract is:

1. the no-override aggregate install invokes the command once in the compiled
   default context's lane;
2. direct domain commands may override to any declared context;
3. `install-user.sh` is not a universal argument router—passing a domain flag to
   it is unsafe because every child receives the same argv;
4. an environment override affecting a composed leaf is allowed only if the
   project explicitly accepts that aggregate scope names describe defaults, not
   hard boundaries.

That fourth point needs a human decision before live deployment. If
`install-user.sh` must be a hard user-scope boundary, the compositor needs to
pin or communicate its selected scope and the child must reject a mismatch. Do
not infer such a security guarantee from the filename alone.

### Keep lifecycle operations distinct

| Term | Contract | Current examples |
|---|---|---|
| Build | Produce a derived artifact from sources. It need not expose or activate it. | `cargo build`; Zim generating `init.zsh` caches. |
| Assemble | Combine selected configuration inputs and validate a candidate, normally committing it where that config is consumed. | `config-run.sh`. |
| Publish | Expose an already known artifact at a destination by copy, link, or managed block. | CONFIG whole copy/link; LINKS; loader block insertion. |
| Activate | Make installed state effective in an application/runtime. | Zim cache generation/loader use; systemd daemon reload and enable/start. |
| Install | The domain's complete ordinary setup, which may orchestrate several of the above. | `install-zim.sh`; systemd unit installation. |

These can be orchestrated together without becoming synonyms. Rust is decisive
counterevidence: [`install-rust.sh`](/vars/common.yaml#L396-L436) publishes an
existing build output, while
[`install-rust-user.sh`](/vars/common.yaml#L437-L459) asks Cargo to build and
install from source. They are genuinely different operations, not scoped copies
awaiting one destination parameter.

Systemd demonstrates the healthy form of reuse: generated wrappers bind
`UNIT_DIR`, `SYSTEMCTL`, and `SUDO_CMD` and source one
[`install-unit.sh`](/files/systemd/install-unit.sh), while the domain operation
still owns link/copy, daemon reload, enable, and start.

## 5. One generic config command instead of nine files per context

The nine files are discoverable, but they encode context, action, and strategy
in a Cartesian filename surface. The implementation is shared already; the
remaining duplication is interface materialization.

### Proposed public surface

Generate one public command, tentatively `config-context.sh`, plus its internal
modules:

```text
config-context.sh [--context NAME] install [CONFIG]
config-context.sh [--context NAME] assemble [CONFIG] [--check|--stdout]
config-context.sh [--context NAME] sync-inputs [CONFIG] [--strategy copy|link] [--seed]
config-context.sh [--context NAME] publish [CONFIG] --strategy copy|link
config-context.sh [--context NAME] inputs list|status|put|enable|disable|remove ...
config-context.sh [--context NAME] status [CONFIG] [--json|--json-array]
```

With no action, it may default to `install`, making the one ordinary command
short. `sync-inputs` is clearer generic vocabulary than “drop-ins,” because the
toolkit also binds direct file inputs. `publish` distinguishes whole-output
delivery from assembly. Existing action words can remain temporary parser
compatibility without generating files.

The compiled config spec needs a domain default context (for example
`defaultContext: user`, sourced from an explicit `CONFIG_CONTEXT`). At present
CONFIG has no default because every wrapper bakes one, while Zim already has
one. Exactly one default should join ordinary package composition; other
declared contexts remain directly selectable. Composing every declared context,
as CONFIG_CONTEXTS currently does by default, conflicts with “one ordinary
default.”

### Manual aliases

Compfuzor should generate no alias file or alias map. An operator may create:

```text
config-context-<declared-context>.sh -> config-context.sh
```

The alias infers only context. Because action is a subcommand, the same optional
alias works for install, assemble, input operations, and status. This is not
status-specific or install-specific behavior; it is context selection attached
to a context-bearing command.

Do not infer actions from names such as `status-config-user.sh`, and do not
support strategy aliases. The Zim `install-zim-<context>.sh` convention can
remain install-only for compatibility; broaden it only if Zim later adopts one
multi-action public command. There is no reason to generate `status-zim-*`
aliases.

### Transition

1. Introduce the one command and prove every current operation through its
   subcommands while the nine wrappers still exist.
2. Make config and Zim the two real users of the shared context-selection truth
   table.
3. Teach BINS to compose a structured invocation of the one command, then stop
   emitting the nine context wrappers.
4. Publish an explicit old-to-new command mapping in the operator guide.
5. Do not automatically prune wrappers from older rendered deployments. A live
   migration may remove known stale files deliberately, consistent with the
   project's no-prune rule.

Because this work has not been deployed to live Zim/Mise, a direct pre-deploy
break is also viable. The staged route is still valuable because it provides an
equivalence checkpoint rather than because compatibility aliases are desired.

## 6. Canonical public vocabulary

| Term | Canonical meaning | Do not use it to mean |
|---|---|---|
| **consumer** | The person, service, or runtime whose mutable state/result is being managed. This is explanatory vocabulary, not necessarily a schema object. | The deployment that produced the donor. |
| **context** | A named runtime binding for one consumer use: root/path selectors, relevant configs, and domain activation destinations. | A privilege mode, action, or copy/link choice. |
| **scope** | A coarse class (`user` or `system`) used for root defaults and ordinary composition membership. | A specific consumer, exact destination, proof of current UID, or permission to sudo. |
| **action** | A user-invokable operation with a contract, such as install, assemble, status, import, or publish. | A scheduling position. |
| **strategy** | How a bounded effect is performed, principally copy versus link. | The whole lifecycle or selected consumer. |
| **phase** | A BINS scheduling lane among independent composed invocations. | Zim's internal install steps or Zim module ordering bands. Use “step” or the domain's own term there. |
| **subsystem** | A domain grouping/provenance and compositor tier such as config, links, systemd, or Zim. | A consumer context or generic lifecycle step. |
| **target** | Avoid in new public context APIs. Use `config` for a recipe selection and `destination` for a path. | Both a recipe name and filesystem endpoint. |

Current confusing names/fields:

- `config-run.sh --target` means a CONFIG recipe, while “target” has also meant
  an install destination in design documents.
- `ConfigContext.install: assemble|copy|link` combines a lifecycle route with a
  delivery strategy. If retained as one concise enum, call it `installMode`, not
  simply `install` or `strategy`.
- `dropins` is generic code but Zim-flavored language; `inputDelivery` or the
  command `sync-inputs` better describes both direct and glob inputs.
- `compose` appears on both BINS records and durable config contexts. Runtime
  context ownership should not be expressed as a negative composition flag.
- `ZIM_CONTEXTS.<name>.config` correctly references a config context, but the
  two namespaces permit different names; documentation should say “activation
  context” versus “config context” when both appear.
- Zim module `phase` values (`core`, `prompt`, and so on) are domain ordering
  bands, unrelated to BINS phases (`identity`, `main`, `units`, `records`).

## 7. Coupling and smells, triaged

### Correctness or pre-live contract issues

1. **Direct Zim status is not complete-install status.**
   `status-zim.sh` checks two projected loader blocks, two cache mtimes, and the
   registry. It does not invoke generic config status, so a modified config can
   appear healthy if its cache is newer. Aggregate `status.sh` also runs the
   registered config-context reporter, but the direct command's advertised
   boundary is ambiguous. Decide and test this before live deployment; the
   recommendation is that complete Zim status include config health.

2. **Scope/default composition and runtime override can disagree.**
   The Zim command is compiled into one scope lane but environment or direct CLI
   can select another context. This is safe from surprise sudo—the Zim path
   explicitly uses `--sudo never`—but can violate a human reading of
   `install-user.sh`. Resolve whether aggregate scope is a default or a hard
   boundary.

3. **The public config status wrapper erases error distinction.**
   The toolkit produces 0 clean / 1 drift / 2 error, but the generated
   `status-config-context-*.sh` maps every nonzero result to 1 so it can join the
   aggregate reporter. A direct diagnostic should preserve errors; use a
   separate aggregate adapter if the aggregate only understands boolean drift.

4. **Durable CONFIG spec evolution is unversioned.**
   `zim.spec.json` rejects old versions explicitly; `config.spec.json` has no
   version despite acquiring contexts and runtime semantics. Add a bounded
   version contract before the next incompatible command/spec migration. This
   does not require a universal JSON-schema system.

### Design debt, not evidence of broken behavior

- **Private compiler import.** `zim_context_compile.py` imports
  `config_context_compile._selector`, coupling a domain compiler to a private
  function and even to its error prefix. Promote a small public path-selector
  compiler module; do not duplicate it.
- **CLI-shaped toolkit API.** Zim directly calls `runConfigToolkit`, which is
  good reuse, but constructs `ToolkitOptions` containing parser/reporting fields
  unrelated to the requested operation. Expose typed config operations beneath
  the CLI (`installContext`, `putInput`, `statusContext`) and keep the CLI as a
  facade.
- **Duplicate/lopsided precedence.** Zim has full context precedence; config has
  baked context plus separate strategy precedence. This will drift once config
  gains one command unless both consume the bounded resolver.
- **Negative ownership through `compose: false`.** Zim proves that a referenced
  config context does not compose its generic installer, but the context does
  not positively name an owner and two domain adapters could still both claim
  it. Move ordinary composition authority to BINS invocation metadata; remove
  `compose` from the durable runtime context when that replacement exists.
- **Ephemeral registry manifest.** Zim reconstructs a temporary LINKS manifest
  from durable `zim.spec.json`. This correctly reuses link semantics, but the
  claim is absent from deployment-wide LINKS audit until Zim runs it. Keep it
  for now; evaluate a durable context-resolved link declaration only if audit
  of these dynamic destinations becomes a concrete need.
- **Status means relationship health, not preferred representation.** CONFIG
  deliberately accepts a matching copy, equivalent link, or local assembly as
  healthy. Preserve that permissive contract, but report the effective next
  install mode separately if users need to know that the ordinary action would
  switch representations.
- **Specs are static; selections are dynamic.** Durable config and Zim specs are
  inspectable authorities, while bound config specs and registry manifests are
  temporary execution projections. That division is healthy. Do not persist
  every resolved HOME/XDG result as another source of truth.
- **Partial complete installs can fail midway.** Zim may leave config installed
  before a loader/cache/registry failure. This is consistent with current
  let-it-fail/permissive behavior provided status explains the partial state.
  Do not promise a cross-tool transaction without a real recovery contract.

## 8. Architecture directions

| Direction | Center and shape | Depth/locality | Impact and risks | Futures kept open |
|---|---|---|---|---|
| **A. Consolidate commands, keep domain-local policy** | Replace nine config wrappers with one command, but let config and Zim each retain their own context precedence and keep current BINS filename inference. Composition uses one remaining thunk or special filename. | Very local, shallow extraction. | Smallest refactor, but precedence and composition debt remain; one-real-command is only cosmetically true if hidden wrapper files are still needed. | Later shared resolver remains possible, but another migration is likely. |
| **B. Bounded context/invocation kernel, domain-owned actions** **(recommended)** | Public path-selector and invocation-selection modules; one config command; explicit BINS structured invocation metadata; complete Zim/systemd/Rust actions stay in their domains. | Deep at two proven seams, local everywhere else. | Medium refactor. Requires careful BINS compatibility and a decision about aggregate scope overrides. Avoids an operation framework. | More domain commands can opt into named contexts or structured composition later without copying implementations or committing to a universal plan. |
| **C. BINS-centric global command registry/router** | Turn all generated tools into registered action/context handlers behind one top-level Compfuzor CLI; BINS becomes both catalog and runtime dispatcher. | Deep but broad and centralized. | Large migration; may reduce direct shell transparency and couples domain CLI evolution to a global router. Current wrapper/report helpers and shell workflows would need redesign. | Strong discovery/completion and global plan inspection if that becomes a product goal. Not justified by this checkpoint. |
| **D. Declarative action/effect plan engine** | Compile config publication, loaders, cache builds, LINKS, systemd activation, and statuses into generic data interpreted by a common executor. | Maximum breadth, low domain locality. | Recreates configuration management inside Ansible; must solve privilege, rollback, retries, outputs, and status semantics before value appears. Rust and Mise expose false similarities. | Remote/deferred execution and universal dry-run, but at disproportionate complexity. Reject for now. |

Direction B best preserves what has been proved. It extracts only seams with two
real consumers, gives BINS the missing ability to compose a parameterized
command, and leaves domain behavior where the vocabulary and recovery rules are
known.

## 9. Sequential architectural checkpoints

Each checkpoint should be separately reviewable and committed. No live
playbook run is implied.

### Checkpoint 1 — selection and scope contract

Write executable truth tables before changing shape:

- CLI > valid manual alias > environment > compiled default;
- explicit CLI bypasses alias parsing;
- only context is inferred from `$0`;
- each action resolves only settings it uses;
- direct domain command versus aggregate compositor behavior is explicit;
- decide whether aggregate scope is a default or a hard boundary.

**Exit evidence:** config and Zim examples, including hostile aliases and
conflicting environment, have one agreed expected result; the parent and human
accept the scope contract.

### Checkpoint 2 — one real generic config command

Add a default config context and route every current toolkit capability through
one multi-action command. Initially keep existing wrappers only as an
equivalence harness, not as the destination.

**Exit evidence:** both user and system test contexts perform assemble,
install, input sync/mutation, whole publication, and status through the one
command; no directory overwrite, donor mutation, implicit sudo, receipt/force
gate, or prune appears; old and new operation results match.

This makes config the second real full-precedence consumer rather than a
hypothetical adapter.

### Checkpoint 3 — extract the bounded runtime kernel

Extract the shared invocation-name resolver from the now-working config and Zim
implementations. Promote `_selector` into a public compile module and keep its
runtime counterpart import-safe. Do not include action execution in this
kernel.

**Exit evidence:** the same selection table runs against config and Zim;
deleting Zim leaves the module exercised by config; LINKS remains unchanged
unless a separately verified selector contract genuinely matches.

### Checkpoint 4 — compose invocations, not filenames

Extend BINS minimally so a command can declare its composed action, scope,
subsystem/lane, and fixed arguments independently of its filename. Use both the
generic config command and Zim as real consumers. Compose only each domain's
ordinary default invocation once.

**Exit evidence:** generated `install.sh`/`install-user.sh` invoke the intended
real command directly with the intended subcommand; no per-context or strategy
wrapper files are emitted; current subsystem ordering and direct leaf
invocation remain intact; neutral `install-zimfw.sh` metadata still works.

Only after this exists should `CONFIG_CONTEXTS.compose` be removed from the
runtime spec and the Zim compiler stop validating that negative flag.

### Checkpoint 5 — deepen config's programmatic API and close status gaps

Put typed operations below `config/toolkit.ts`'s CLI facade. Have Zim call those
operations without fabricating CLI option objects. Decide whether
`status-zim.sh` is activation-only or complete; recommended behavior is complete
config + activation status with domain-local aggregation.

**Exit evidence:** matching copy/link/local assembly remain healthy; weird or
unsupported states remain visible; direct status preserves clean/drift/error;
aggregate status adapts without destroying direct diagnostics; Zim user/system
install, producer import, and status retain Build 5 behavior.

### Checkpoint 6 — compare a second composite domain before any plan engine

Use **systemd unit installation** as the preferred tracer bullet. It already has
one implementation behind user/system wrappers and combines publication,
daemon reload, enable, and start. Ask whether structured BINS invocations and
the selection kernel help it without turning those steps into generic plan
data.

Also use:

- **LINKS** to test only shared destination/effect and possibly selector seams;
  preserve its durable ownership/policy/privilege contract;
- **Mise Bash blocks** as a negative control: two independent managed blocks
  need status, not CONFIG assembly or a context-install framework;
- **Rust/global bins** as a negative control for lifecycle collapse: artifact
  publication and `cargo install` must remain different operations.

**Exit evidence:** a comparison note identifies an exact second shared behavior
with matching inputs, failures, and status semantics—or records that no further
extraction is warranted. A generic plan proposal is allowed only after that
evidence.

## 10. What should not be generalized now

- Zim's two-channel schema, loader projection, shell quoting, legacy cleanup,
  controller, emergency path, caches, registry, or producer layout.
- A universal install/build/activate/publish action graph.
- A universal transaction or rollback protocol across external tools.
- `$0`-based action or strategy inference, generated aliases, or a Cartesian
  alias catalog.
- Automatic pruning, ownership receipts, force ceremony, or historical state
  databases for the permissive config toolkit.
- Implicit privilege escalation from scope or context selection.
- A single status ontology that calls every matching copy/link/block/build the
  same relationship.
- Recasting CONFIG copy/link operations as durable LINKS records; share effects,
  not ownership contracts.
- Folding Mise's independent blocks into CONFIG assembly merely because both
  touch shell startup files.
- Unifying Rust's system publication and Cargo-managed user installation.
- Named contexts for every subsystem before a concrete second use requires
  runtime choice rather than generated bindings.
- A global `compfuzor` command router, remote executor, all-user enumerator, or
  generic filesystem effect plan.

## Decisions still requiring human confirmation

1. **Default composition:** should exactly one configured context per domain
   join ordinary install composition? Recommendation: yes; other contexts are
   direct selections.
2. **Aggregate scope:** is `install-user.sh` a default grouping or a hard
   user-scope boundary? Recommendation: treat direct domain commands as freely
   selectable, but decide explicitly whether environment overrides may cross a
   composed aggregate's lane.
3. **Generic command name and default action:** `config-context.sh` with default
   `install` is recommended; `config.sh` should remain the lower-level assembly
   runner rather than absorb toolkit dispatch.
4. **Manual alias reach:** should `config-context-<name>.sh` infer context for all
   subcommands? Recommendation: yes; never infer action or strategy.
5. **Zim status boundary:** should direct `status-zim.sh` include generic config
   health? Recommendation: yes, because install is advertised as complete.
6. **Direct status exits:** preserve 0/1/2 clean/drift/error and adapt only at
   aggregate status. Recommendation: yes.

None of these choices requires generalizing Zim's internal install sequence.

## Cross-references

- [`assessment0.unknown.md`](/.design/config-user-target/assessment0.unknown.md)
  established consumer-bound configuration, shared effects, and distinct
  assembly/publication/activation responsibilities. This assessment narrows the
  next extraction to invocation selection and composition records.
- [`build5.solx.md`](/.design/config-user-target/build5.solx.md) and
  [`build5-review0.solx.md`](/.design/config-user-target/build5-review0.solx.md)
  are the implemented behavior to preserve: one Zim installer, manual aliases,
  explicit loader sources, and user/system proof.
- [`consumer-toolkit.md`](/doc/config/consumer-toolkit.md) documents the current
  nine-wrapper surface and permissive representation/status contract; it would
  need an old-to-new command mapping after command consolidation.
- [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
  is the present generic context compiler and the source of both the reusable
  path model and wrapper explosion.
- [`config/toolkit.ts`](/files/config/toolkit.ts) is the deep config operation
  implementation that should survive behind a smaller public command and a
  typed programmatic API.
- [`zim_context_compile.py`](/library/filter_plugins/zim_context_compile.py) and
  [`zim/install.ts`](/files/zim/install.ts) demonstrate both sides of the
  boundary: valid Zim domain fields and duplicated invocation policy.
- [`doc/bins.md`](/doc/bins.md) and [`doc/subsys.md`](/doc/subsys.md) define BINS
  as action/scope/subsystem composition. A structured invocation extends that
  role without making BINS an install executor.
- [`links/delivery.ts`](/files/links/delivery.ts) and
  [`links/links.ts`](/files/links/links.ts) show the successful precedent of a
  shared effect kernel beneath distinct ownership/status contracts.
- [`vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks) and
  [`systemd/install-unit.sh`](/files/systemd/install-unit.sh) are the preferred
  next comparison for one scoped implementation behind domain bindings.
- [`mise.opt.pb`](/mise.opt.pb) is the non-assembly counterexample: independent
  managed blocks and settings remain coherent without CONFIG_CONTEXTS.
- [`vars/common.yaml`](/vars/common.yaml#L366-L469) is the lifecycle
  counterexample: Rust build-output publication and Cargo installation are
  intentionally different operations despite system/user naming.
