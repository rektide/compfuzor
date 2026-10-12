---
type: RecoveryReport
title: Recovered ambition and current world for the CFR reset
description: Discovery report recovering the ambitious compfuzor-runtime (cfr) reset design corpus, its human direction and rulings, the experiments and rejections, what shipped since, and an evidence-grounded handoff for a fresh architecture assessment.
resource: /design/runtime-direction/recovery0.glm53fx.md
tags: [compfuzor, cfr, runtime, effect, workflow, composition, recovery, handoff]
status: draft
generated: { by: 'model:zai/glm-5.3-flash-max', at: '2026-10-12' }
verified: { by: 'model:zai/glm-5.3-flash-max (source + on-disk inspection; read-only /opt observation; no runs)' }
stale_after: 2026-11-12
sources:
  - id: session
    resource: opencode://ses_ed1828035ffeQZRqowNSaNvDFK
    title: proud-lagoon — FX discovery wave, corpus recovery and current-world mapping
  - id: parent
    resource: opencode://ses_ed3f4aaaaffePYlWeomteOWlbg
    title: brave-meadow — operator commission to recover the ambitious reset before a fresh assessment
  - id: survey
    resource: /design/runtime-direction/docs-survey0.glm53fx.md
    title: Prior FX survey of the corpus through Sep 29 (five adoption meanings, chronology)
  - id: brief
    resource: /design/compfuzor-runtime/composition-problem0.gpt6a.md
    title: Sep 26 operator brief reopening the runtime model
  - id: disposition
    resource: /design/compfuzor-runtime/experiments0.gpt6a.md
    title: Sep 26 four-experiment disposition and admission limits
  - id: draft2
    resource: /design/compfuzor-runtime/effect-draft2.gpt6a.md
    title: Sep 29 latest architecture synthesis (annotated native exports, init, run data, history)
  - id: envdirection
    resource: /design/compfuzor-runtime/environment0.gpt6a.md
    title: Oct 12 selected-environment direction after the proxy adoption
  - id: definitions
    resource: /doc/config/definitions.md
    title: Shipped independent CONFIGs and env.d baseline
---

# Recovering the ambitious CFR reset

## Situation and method

The operator asked (via [brave-meadow](opencode://ses_ed3f4aaaaffePYlWeomteOWlbg))
to find the previous, *very ambitious* reset/rebuild design work for **cfr** (the
proposed short name for a new compfuzor runtime), because much has been built
since; a fresh Astra-medium assessment and draft follow. This document is the
discovery stage only: it recovers sources, rulings, relationships, and status,
and maps them to current code. It does not propose the new architecture.

Method: full reads of the runtime-direction and compfuzor-runtime corpora plus
the config-anneal originals; maintained `doc/config` and `doc/actions` truths;
the fuzings/registry-discovery/action-audiences/runtime-sourcing implementation
waves; `jj log` chronology; targeted source and test inventory; one read-only
`ls` of the live `/opt/zim-main` deployment. The earlier
[FX survey](/design/runtime-direction/docs-survey0.glm53fx.md) (Sep 29) remains
accurate for its scope and is heavily reused; this report extends it through
Oct 12 and refocuses it on the *reset* ambition rather than the adoption
mismatches that motivated that survey.

## The ambition, reconstructed

The reset is a deliberate replacement of the current partial runtime —
generated shell compositors plus a read-only catalog plus an opt-in flow
executor — with **cfr, a composable runtime environment for domain modules**.
The through-line across the corpus:

1. **The existing runtime is evidence, not constraint.** "Existing types, flow
   names, schemas, and implementation language choices are evidence to assess,
   not constraints that must survive. Significant rework is welcome"
   ([composition-problem0](/design/compfuzor-runtime/composition-problem0.gpt6a.md#why-this-work-exists),
   Sep 26 operator brief). The Sep 14 anneal's flows/indexed-file mechanics are
   explicitly historical after this brief.
2. **Composition and contribution are the centerpiece.** The operator wants:
   navigable specificity (adding filename components narrows, removing
   broadens — reflected in library tools and the cfr CLI, not only generated
   filenames); visible identity in executable names/paths; easy broad
   contributions (TypeScript modules exporting standard self-description,
   including tags; scripts must query the registry and participate too).
3. **The single-tree material placement problem gets a bold pass.** Material
   locations, exposure locations, relativity, and link direction must be
   explicit enough for the runtime to understand and use; "containered" was
   rejected as a name; *material/exposure/placement* is a candidate framing,
   not a mandated model. Confext artifact **building** was the first concrete
   deliverable; installation/activation stays out of scope.
4. **Shared runtime is on the table early.** The operator will accept stronger
   host prerequisites and a host-common runtime over per-deployment
   distribution; bootstrap ordering, version compatibility, and missing-runtime
   behavior are required design content (tracked as
   **compfuzor-runtime-bootstrap**; `cf-r` was the shared-runtime deployment
   idea, not an existing tool; command spelling unsettled).
5. **Execution controls are preserved:** composition must not silently auto-run
   apply, bypasses stay distinguishable, building an artifact must not imply
   activating it.
6. **Effect was chosen as the execution foundation** after four architectural
   experiments ([experiments0](/design/compfuzor-runtime/experiments0.gpt6a.md#experiment-4-parent-assessment-and-end-of-sequence)
   closed with "no completed backbone"; the operator then pivoted:
   [effect-draft0](/design/compfuzor-runtime/effect-draft0.gpt6a.md#1-decision-and-scope)
   "Effect is the execution foundation", CFR-scope only). Later drafts moved
   from a bespoke CFR program AST toward **upstream Effect Workflow/Activity**
   with thin CFR admission ([draft1](/design/compfuzor-runtime/effect-draft1.gpt61sol.md#1-central-proposal-use-upstream-composition-add-thin-admissiondiscovery)),
   then settled on **annotated native exports** with no mandatory module
   envelope ([draft2](/design/compfuzor-runtime/effect-draft2.gpt6a.md#direction-and-status)).
7. **Sep 29–30 refinements (operator clarifications recorded in the drafts):**
   BINS-first "80%" admission before interpreting script internals;
   semi-recursive declared-membership collection (not a universal graph);
   configuration as *named multi-step pipelines*; native TS modules both
   importable and directly runnable (`runIfMain`); mutable collaboration is
   **normal** (contributions may change shared state through a typed
   `RunData` service); an extensible shared init stage; durable invocation
   history by default; no file/content cataloging prerequisite for executing
   useful work.
8. **The honest-inspection epistemology must survive every draft:** catalog,
   resolved plan (exact for explicit structures, dynamic/opaque marked), and
   execution trace are three levels no one of which may masquerade as another;
   opaque legacy operations remain honest leaves; no speculative dry-run of
   generators with invented return values.
9. **Admission limits on legacy state** (the "limits" the operator remembers):
   no premature global task graphs; no mandatory CFR receipts for legacy
   inputs (reuse existing build evidence; adapters describe known-vs-assumed);
   no forced confext dependency on a fully project-contained layout; no new
   round of toy experiments by default.

The most recent direction (Oct 12) does not shrink this ambition but *starts*
it at a narrow selected-environment slice:
[environment0](/design/compfuzor-runtime/environment0.gpt6a.md) (selection
first, defaults retained as inspectable data, managed-vs-local comparison in
new cfr) and the completed independent probe
[environment1](/design/compfuzor-runtime/environment1.gpt61sol.md#recommendation)
(selected-default snapshot + pure CFR resolver + nonexported shell-local
receipt, explicitly **not** a global env manager). Both point at cfr's shared
init/run-data as the eventual home.

## Human direction vs agent proposals (who decided what)

| Date | Ruling / direction | Source | Standing |
|---|---|---|---|
| Sep 11–13 | Config consumer toolkit built; fixed six-command CONFIG surface; simplification guardrails ("delete layers, don't add frameworks") | [simplification.md](/doc/config/simplification.md#position), [config-context/command0.solx.md](/design/config-context/command0.solx.md) | Accepted product contracts; deletion test still governs |
| Sep 13 | systemd is **not** a CONFIG context; do-not-generalize list | [install-context/systemd0.unknown.md](/design/install-context/systemd0.unknown.md) | Accepted counterexample, still binding |
| Sep 13–14 | Anneal: contributors inject attributed data into flows; read-only catalog first; opt-in flow execution | [execution-model0](/design/config-anneal/execution-model0.gpt6.md#status-and-intent) | Partially implemented; **historical roadmap** after Sep 26 |
| Sep 13–14 | Effect evaluated as implementation substrate only; durable workflow machinery deliberately not adopted | [effect-design0](/design/config-anneal/effect-design0.glm53.md#whats-up) | Superseded in scope by the Sep 26+ reset |
| Sep 14 (impl) | Attribution + read-only catalog + direct final CONFIG compile + opt-in flow execution (build/install/status only) | [log.md 2026-09-14](/doc/config/log.md#2026-09-14) | Shipped; shell compositors remain execution authority |
| Sep 18 | Assessment: dormancy; zim-main file→symlink migration failure; no-force + no-prune collision; `BINS_ABSENT` named as mechanism | [assess0 §5](/design/compfuzor-runtime/assess0.glm53fm.md) | Diagnosis accepted; remediation **still pending on disk today** (verified below) |
| Sep 26 | Operator reopens the runtime: registry + composition ambition, single-tree bold pass, shared runtime on table, runtime-is-evidence ruling, design tests and open decisions enumerated | [composition-problem0](/design/compfuzor-runtime/composition-problem0.gpt6a.md#operator-direction-to-preserve) | **The governing human direction** for the reset |
| Sep 26 | Operator authorizes four sequential Sol experiments, then closes them: no completed backbone; retained ideas enumerated; recommended reinterpretation; explicit limits | [experiments0](/design/compfuzor-runtime/experiments0.gpt6a.md#experiment-4-parent-assessment-and-end-of-sequence) | Closed; no fifth probe authorized |
| Sep 26 | Operator chooses Effect (CFR scope only) after the experiments | recorded in [effect-draft0 §1](/design/compfuzor-runtime/effect-draft0.gpt6a.md#1-decision-and-scope) | Chosen direction; interfaces reviewable; unimplemented |
| Sep 29 | Operator: BINS-first 80% admission; Workflow/Activity as core; semi-recursive aggregation; config pipelines; native TS modules; no cataloging prerequisite | recorded in [effect-draft1 "What changed"]( /design/compfuzor-runtime/effect-draft1.gpt61sol.md#what-changed) | Direction, not accepted spec |
| Sep 29 (late) | Operator: mutable collaboration is normal; extensible shared init; default runtime-directory discovery | recorded in [effect-draft2](/design/compfuzor-runtime/effect-draft2.gpt6a.md#direction-and-status) | Direction, not accepted spec |
| Sep 30 | Astra research (commissioned): Firmament borrowings ranked by Effect naturalizability; "choices to discuss, not accepted expansion" | [firmament-candidates0](/design/compfuzor-runtime/firmament-candidates0.gpt6a.md#finding) | Unaccepted research input |
| Oct 1–7 | Operator directions in *adjacent* implementation waves: rendezvous registries with mask/unmask; runtime source policy `changed → canonical → deployed` with SHA-512 deployment burns; audience actions | [runtime-sourcing/direction0-syn](/design/runtime-sourcing/direction0-syn.gpt61sol.md#what-is-up), [registry-discovery/README](/design/registry-discovery/README.md), [doc/actions/README](/doc/actions/README.md) | Partially shipped outside cfr; **constraints on cfr discovery/bootstrap** |
| Oct 11–12 | Multi-CONFIG + env.d baseline shipped, then proxy-first ENV adoption; operator direction: select env narrowly, retain defaults in **new cfr** | [definitions.md](/doc/config/definitions.md), [proxy0](/design/fuzings/proxy0.gpt61sol.md), [environment0](/design/compfuzor-runtime/environment0.gpt6a.md) | Shipped baseline + newest human direction into cfr |
| Oct 12 | Independent Sol probe: selected view + pure resolver + shell-local receipt; narrowed first slice | [environment1](/design/compfuzor-runtime/environment1.gpt61sol.md#recommendation) | Evidence + proposed slice, not accepted policy |

Agent-proposal lineage (independent waves, none synthesized into an accepted
spec): composition-draft0 (parent) vs composition-draft1.glm53 (one registry,
host `cfr`, declared exposures) vs composition-draft1.sxh (host runtime over
project-local route joins + publication ledgers); effect-draft0 → draft1 →
draft2. **No `draft-syn` synthesis of the composition wave exists**, and no
accepted synthesis reconciles execution-model0 with the Sep 26 reopen — the
docs-survey flagged both absences and they persist.

## Prioritized reading map for the assessor

Tier 1 — the ambition itself (read fully):

1. [composition-problem0.gpt6a.md](/design/compfuzor-runtime/composition-problem0.gpt6a.md)
   — Sep 26 operator brief: preserved direction, concrete design tests
   (§Concrete design tests), open decisions (§Decisions still open),
   bootstrap clarification. The reset's charter.
2. [experiments0.gpt6a.md](/design/compfuzor-runtime/experiments0.gpt6a.md)
   — parent assessments of the four probes; §"Retain as architectural
   evidence", §"Reject a claim of a completed backbone", and the final
   recommended reinterpretation + limits. What is settled vs merely learned.
3. [effect-draft2.gpt6a.md](/design/compfuzor-runtime/effect-draft2.gpt6a.md)
   — the latest synthesis and de facto current architecture proposal:
   annotated native Activities/Workflows (§2), default discovery (§3),
   extensible shared init (§4), mutable typed run data + replay agreement
   (§5), ordering/recursive aggregation (§6), invocation binding + durable
   history (§7), BINS-first admission (§8), concrete walks (§9), and the five
   required checkpoint demonstrations (§10).
4. [effect-draft0.gpt6a.md](/design/compfuzor-runtime/effect-draft0.gpt6a.md)
   and [effect-draft1.gpt61sol.md](/design/compfuzor-runtime/effect-draft1.gpt61sol.md)
   — the lineage: what Effect owns vs CFR owns (draft0 §2), yieldable
   descriptions and the three inspection levels (draft0 §§3–4), the
   BINS 80% adapter table and opaque/expanded aggregate rule (draft1 §2).
5. [environment0.gpt6a.md](/design/compfuzor-runtime/environment0.gpt6a.md) +
   [environment1.gpt61sol.md](/design/compfuzor-runtime/environment1.gpt61sol.md)
   — newest direction and its narrowed, evidence-backed first slice. Narrow;
   do not let it displace the broad assessment.

Tier 2 — grounding, guardrails, and counterweights:

6. [world-map0.gpt61sol.md](/design/compfuzor-runtime/world-map0.gpt61sol.md)
   — present-world authorities table, the four provider roles (§3), concrete
   Zim/Mise/MCP/OpenCode walks (§4), Workflow-vs-plain-Effect comparison (§5).
   The bridge from draft0 to draft1; its "missing centerpiece" conclusion
   (shared contribution discovery/composition authority) still holds.
7. [docs-survey0.glm53fx.md](/design/runtime-direction/docs-survey0.glm53fx.md)
   — the five meanings of "adoption" (§First), the verified
   implementation-vs-intent snapshot, and the historical reading route
   (execution-model0, simplification.md, use-cases1).
8. [doc/config/README.md](/doc/config/README.md) +
   [definitions.md](/doc/config/definitions.md) — shipped truth: six fixed
   commands, the `config-` compositor lane coexistence, complete-definition
   baseline, ENV literal grammar. Everything here is *compatibility surface*
   the reset must migrate or deliberately retire, not silently keep.
9. [doc/config/simplification.md](/doc/config/simplification.md#position) —
   preserved product contracts (L32–46) and the deletion test; the counterweight
   to registry ambition (tension 4 in the survey).
10. [assess0.glm53fm.md](/design/compfuzor-runtime/assess0.glm53fm.md) — why
    representation migration is the standing production sore spot; also the
    effort's philosophy summary (§1).
11. [execution-model0.gpt6.md](/design/config-anneal/execution-model0.gpt6.md#annealing-and-implementation-matrix)
    — historical matrix; reconcile its vocabulary (contributor/action/
    invocation/flow, attribution, multi-plane bypass) rather than its compiled
    flow mechanics. Its attribution and deny-only bypass distinctions are
    carried forward by every later draft.

Tier 3 — adjacent built waves that constrain or prefigure cfr:

12. [runtime-sourcing/direction0-syn.gpt61sol.md](/design/runtime-sourcing/direction0-syn.gpt61sol.md#2-keep-three-catalogs-and-two-roots-distinct)
    — operator's `changed → canonical → deployed` sourcing preference, SHA-512
    burns, three-catalogs/two-roots separation; **unimplemented**; supplies
    the source-root resolution question for cfr discovery (draft2 §3).
13. [design/registry-discovery/README.md](/design/registry-discovery/README.md)
    and [runtime/registry/README.md](/runtime/registry/README.md) — shipped
    provider/consumer rendezvous with masks and force-enable; a working,
    domain-scoped instance of "registry describes, domain interprets".
14. [doc/actions/README.md](/doc/actions/README.md) and
    [design/action-audiences/index.md](/design/action-audiences/index.md) —
    shipped opt-in audience `.mjs` action families with typed CONFIG/keybinding
    context binding; resembles cfr's per-deployment entry projections.
15. [design/fuzings/](/design/fuzings/checkpoint0.gpt61sol.md) —
    [contract1](/design/fuzings/contract1.gpt6a.md) /
    [implementation0](/design/fuzings/implementation0.gpt6a.md) /
    [checkpoint0](/design/fuzings/checkpoint0.gpt61sol.md) (experimental
    native-root resolver, deferred) /
    [proxy0](/design/fuzings/proxy0.gpt61sol.md) (completed adoption, explicit
    limits: no managed refresh, whole-export loading retained).
16. [firmament-candidates0.gpt6a.md](/design/compfuzor-runtime/firmament-candidates0.gpt6a.md)
    — ranked borrowings for RunData layering/provenance; §"The important
    Effect boundary" (three equivalences that do not hold).
17. [design/confext/build-inputs1.fx.md](/design/confext/build-inputs1.fx.md)
    (corrected confext evidence) and
    [runtime0.sm.md](/design/confext/runtime0.sm.md) (verified runtime limits;
    "incremental first, remake conditional" counterweight).
18. [doc/config/log.md](/doc/config/log.md) — dated deployment evidence,
    including what was deliberately pruned and what the Vite+ cutover did.

Scratch probes (gitignored, untracked oracles — useful to run, not to ship):
`.test-agent/cfr-backbone/experiment{1..4}/` (the four backbone probes),
`.test-agent/cfr-effect/experiment0/` (the Effect-native GX probe),
`.test-agent/cfr-environment/` (the selected-environment probe; committed
report + scenario tests, code intentionally untracked).

## Experiments, competing designs, and rejected conclusions

**The four backbone probes (closed, Sep 26).** Reports:
[experiment1](/design/compfuzor-runtime/experiment1.sxh.md),
[experiment2](/design/compfuzor-runtime/experiment2.sxh.md),
[experiment3](/design/compfuzor-runtime/experiment3.sxh.md),
[experiment4](/design/compfuzor-runtime/experiment4.sxh.md).
Retained: collection ≠ implementation selection; programs as contributions;
structured material descriptions; checkout-local global exposure without a
pre-installed runtime ("executable location is not deployment identity");
realization/exposure/artifact state as separate observations; persisted
realization evidence permits packaging existing bytes (without requiring
receipts); repeated authored calls are occurrences — equality does not justify
execution reuse. Rejected: the completed-backbone claim (experiment 4 is "a
small dependency binding/registration mechanism and async dispatcher"); global
dedup of overlapping authored calls (experiment 2's `seen`-based no-op reuse);
ID-sort-as-prerequisites; WeakMap-keyed inspection that cannot detect byte
drift (experiment 3).

**Competing composition shapes (unresolved).** One compiled registry with
projections ([composition-draft1.glm53.md](/design/compfuzor-runtime/composition-draft1.glm53.md))
vs host runtime over route joins + publication ledgers
([composition-draft1.sxh.md](/design/compfuzor-runtime/composition-draft1.sxh.md))
vs explicit membership + nested operations
([composition-draft0.gpt6a.md](/design/compfuzor-runtime/composition-draft0.gpt6a.md)).
None accepted; draft2's annotated-native-export direction supersedes the
mandatory-envelope variants but the registry-vs-ledger question reappears
wherever selection/provenance must be explained.

**The program-form debate (draft0 vs draft1/2).** draft0 kept a small CFR
program structure (call/sequence/group/effect-body) as inspectable data;
draft1/2 moved to upstream Workflow/Activity definitions annotated for
admission, with dynamic bodies honestly opaque. The question "does CFR need
its own authored program tree" was explicitly reopened by
[world-map0 §2](/design/compfuzor-runtime/world-map0.gpt61sol.md#2-what-effect-draft0-actually-defined)
and answered provisionally (no) by draft2 — an assessor should re-test rather
than inherit it.

**Standing guardrails and counterweights.** simplification.md's deletion test
and preserved contracts; confext runtime0.sm's "incremental first, remake
conditional"; systemd's scope-≠-context precedent; effect-draft0's "durable
execution is a different question" (Workflow/Activity are not automatically
the runner; saved results do not prove present state); draft2's replay
constraints (cached Activity results must not silently drop state updates;
EventLog runs handlers *before* commit and is not a write-ahead transaction
around host effects); firmament's three non-equivalences (contribution ≠
`Layer`; reactive dependency ≠ recorded support; replay ≠ semantic cache).

**Known criticism of the current runtime to carry** (docs-survey §C–E):
the `config`/`apply` lane-vs-flow divergence (filename grammar deepening
what the anneal wanted to retire); the missing native config-flow projection;
no recorded live flow-execution run; the no-prune + no-force migration
collision. The apt-lane assessment's framing stands: the consequential
decision is *domain action vs aggregate flow*, not which language executes a
leaf ([assessment0](/design/runtime-config-lane/assessment0.gpt61sol.md)).

## Built since the design wave — mapping to docs and code

The Oct 1–12 work shipped substantial capability *outside* cfr. For each:
whether it fulfills, constrains, or merely resembles the older goals.

| Shipped capability | Maintained doc | Code / tests | Relation to the cfr ambition |
|---|---|---|---|
| **Registry rendezvous library** (provider/consumer symlink collections, owner-held descriptors, masks, invocation-only force-enable) | [doc/config/keybindings.md](/doc/config/keybindings.md), [producers](/doc/config/keybinding-producers.md), [consumers](/doc/config/keybinding-consumers.md), [runtime/registry/README.md](/runtime/registry/README.md) | `runtime/registry/{model,policy,read,register,guard}.ts`; `library/filter_plugins/keybindings_compile.py`; `tests/integration/keybindings*.py`, `tests/config-keybindings/` | **Resembles + constrains**: a working instance of "registry describes, domain interprets", but keybinding-scoped with closed membership; cfr discovery (draft2 §3) must not duplicate or silently subsume its policy (masks, force-enable, disabled advertisement) |
| **Audience actions** (opt-in `ACTION_AUDIENCES`, `.mjs` action families, typed CONFIG/keybinding bindings, pre-effects admission, no user→system fallback) | [doc/actions/README.md](/doc/actions/README.md), [action-audiences index](/design/action-audiences/index.md) | `files/actions/*.ts`, `library/filter_plugins/{action_audiences,action_contexts}.py`; `tests/integration/action_*.py` | **Resembles**: prepared per-audience entries + spec-driven invocation is close to cfr's compatibility entry projection (draft0 §6 "thin commands selecting the same program"); environment0 explicitly warns **not** to mistake this for the completed new cfr |
| **Independent complete CONFIG definitions** (`CONFIG_DEFINITIONS`, per-definition recipes/contexts/owners, binding envelopes, collision checks) | [definitions.md](/doc/config/definitions.md#independent-complete-configs) | `library/filter_plugins/config_definitions.py`; `tests/integration/config_definitions.test.py`, `zim_consumer.test.py` | **Constrains**: multi-CONFIG reality the reset must represent (each definition a candidate cfr "domain module"); shares one stock worker — exactly the duplication cfr's shared runner intends to replace |
| **Explicit env.d ENV CONFIG** (opt-in `ENV_CONFIG`/`ENV_CONTRIBUTIONS`, literal grammar, exact projections `env`/`env-export`/`env-zsh`) | [definitions.md §Literal grammar](/doc/config/definitions.md#literal-grammar-and-projections) | `library/filter_plugins/env_compile.py`; `files/config-env.py` (reducer deployed); `tests/filter_plugins/env_compile.test.py` | **Fulfills narrowly + constrains**: literal selection-with-projections matches draft2's "environment as run data, not process.env" and environment0's selection-first; source-time only — managed refresh intentionally left to new cfr (environment0/1) |
| **Proxy-first adoption** (service/client projections, build-order prerequisites, preserved runtime shell defaults, envdefault preference restored) | [proxy0](/design/fuzings/proxy0.gpt61sol.md) | `opencode-bus-proxy.src.pb`; `files/opencode-bus-proxy/opencode-proxy-env.zsh`; `tests/integration/proxy_env_adoption.test.py` | **Fulfills the narrow concrete case**; its explicit limits (re-sourcing preserves stale args; no last-applied state) are environment0/1's motivation, not evidence against the broad reset |
| **config-remote multi-target fanout** (`put-matching`, per-target admission/rollback) | [definitions.md §Remote input delivery](/doc/config/definitions.md#remote-input-delivery) | `files/config-remote/runtime.ts`; `tests/integration/config_remote.test.py` | **Constrains**: one input → several consumer bindings is draft2 §9's worked case; the shipped transactional semantics (admit-then-mutate, per-target rollback) are behavior to preserve or consciously re-home |
| **Experimental fuzings native-root resolver** (enrolled roots, recognition, disable without prune) | [checkpoint0](/design/fuzings/checkpoint0.gpt61sol.md) | `files/config/fuzings.ts`; `tests/integration/config_fuzing_checkpoint.test.py` | **Deferred predecessor**: status "experimental"; deliberately not promoted; relevant to material placement later |
| **Runtime sourcing direction** (`changed → canonical → deployed`, SHA-512 burns, three catalogs/two roots) | [direction0-syn](/design/runtime-sourcing/direction0-syn.gpt61sol.md) | none (design only) | **Constrains cfr directly**: bootstrap/discovery must separate implementation-provider identity from deployment identity; recordable policy, not baked launcher logic |
| **Contained experiments & rehearsal** (zim2/mise2; fresh-account rehearsal with bootstrap gaps) | [zimtest-rehearsal.md](/doc/config/zimtest-rehearsal.md), [assess0](/design/compfuzor-runtime/assess0.glm53fm.md) | `zim2.opt.pb`, `mise2.opt.pb` | Evidence: catalog authority works contained; production Zim/Mise do not opt in |
| **Effect presence** | — | `package.json` `effect@4.0.0-rc.118` (+platform); `runtime/{cli,zim,keybindings}/registry.ts` import `Schema`; archive toolkit CLI is separately Effect4-implemented (`archive/src/cli/commands/*.ts`) | **Note**: Effect is already a real (narrow) dependency of the shipped multicall runtime, and the archive CLI proves Effect4 in production elsewhere; the "Effect is CFR-scope only" framing from draft0 is about *architecture adoption*, not package availability |

**What has *not* changed:** generated shell compositors remain the execution
authority; the catalog is read-only unless a deployment opts into experimental
flow execution (build/install/status only); no authored `composition:`
declarations exist; no native config/apply flow projection; no host-common
`cfr`; none of effect-draft0/1/2 is implemented in the runtime; the Firmament
borrowings are unaccepted research. The environment1 probe is scratch, not
shipped. **Astra must not mistake any of the above shipped work for the reset,
nor the reset drafts for shipped behavior.**

### Current code/test orientation (entry points only)

- Multicall dispatcher: `files/runtime/compfuzor-runtime.ts` (build via Vite+
  to checked-in `runtime/compfuzor-runtime.mjs`); domains under
  `files/{config,config-remote,catalog,flow,links,zim,actions}/`; registry
  library under `runtime/registry/`; discovery/keybindings under
  `runtime/discovery/`, `runtime/keybindings/`.
- Controller-side compilers: `library/filter_plugins/` (`bin_composers.py`,
  `runtime_catalog.py`, `config_compile.py`, `config_definitions.py`,
  `env_compile.py`, `keybindings_compile.py`, `fuzings.py`,
  `action_audiences.py`).
- Wrappers/templates: `files/_bin`, `files/_helpers/env`, `files/config-run.sh`,
  `files/config-env.py`.
- Tests: `tests/integration/*.test.py` (config_definitions, zim_consumer,
  proxy_env_adoption, config_fuzing_checkpoint, catalog_flow, action_*,
  keybindings_*), `tests/config-keybindings/`, Vitest suites for TS domains.
- Live deployment state (observed read-only, 2026-10-12): `/opt/zim-main` still
  has the assess0 §5 damage — `bin/config/command.mjs` absent (six fixed
  command symlinks dangle), `bin/zim/` empty, `bin/links/` populated;
  `compfuzor-catalog.sh` present. No repair has been recorded since Sep 29.
  This is the standing representation-migration evidence: a fresh runtime
  design will be judged against exactly this adoption class.

## Unresolved architecture questions for the assessment

1. **Program form and truthful inspection.** Annotated native
   Activities/Workflows (draft2) vs explicit CFR structures (draft0 §4) vs
   declared outlines; how narrow/broad navigation (operator design test 1),
   stage barriers, and complete-child-pipelines-vs-staged-bars (draft2 §6)
   coexist; what `cfr plan/explain` may promise.
2. **Discovery, sourcing, and bootstrap as one question.** draft2's default
   `RUNTIME_DIR` scan + runtime-sourcing's `changed → canonical → deployed`
   policy + compfuzor-runtime-bootstrap self-install + version compatibility
   + missing-runtime behavior have never been designed together. The
   three-catalogs/two-roots separation is the existing ruling to build on.
3. **Mutable run data + replay agreement.** draft2 §5's update-outside-cached-
   body rule, the stateful managed-Activity helper, Firmament's layered
   contributions/winner provenance/input projections — which subset becomes
   the first contract, and what the environment0/1 selected-env view (snapshot
   + pure resolver + shell receipt) reuses from it.
4. **BINS admission boundary.** Opaque vs expanded aggregates; authored-root
   bodies (OpenCode `build.sh` merge rule); exit/skip protocol honesty;
   become/privilege routing; what shell composition is actually retired first
   (draft1 §8's checkpoint list).
5. **Registry vs ledger for selection provenance** — the unresolved
   composition-draft1 fork; interacts with the shipped registry library's
   masks/force-enable and with config-remote's per-target admission.
6. **Configuration pipelines** as the first substantive domain (world-map0's
   upgrade of confext-first): Zim/Mise/MCP/OpenCode walks vs confext build;
   relationship of shipped `CONFIG_DEFINITIONS`/ENV to future domain modules.
7. **History and durable resumption.** EventLog/SQL-journal integration,
   secret-aware projections, memory-engine-first vs durable engine choice
   (draft2 §7); what "durable history by default" minimally means.
8. **Migration/adoption policy.** The no-prune/no-force collision, the
   dangling zim-main surface, and how the reset avoids repeating
   assess0's failure class (representation cutover with `BINS_ABSENT`-style
   mechanisms or an explicit remediation slice).
9. **What gets deleted.** Every draft promises retirement of the partial
   flow executor, filename-derived composition, and the experimental string
   service locator — a new draft should name its deletion list against
   simplification.md's contracts.

## Known missing or unlocated sources; stale-doc caveats

- **cotail:// URNs**: the Sep 26 operator direction lives only as
  `cotail://ses_f2198adecffeZm5gWy0G9BCV3h` ("quiet-tiger") in
  composition-problem0/experiments0/effect-draft0 frontmatter; resolvability
  in the current store is unverified. The four-experiment authorization and
  the Effect pivot cite the same URN. Treat the drafts' recorded summaries as
  the recoverable form of that direction.
- **No session URIs for the Sep 29 clarifications**: effect-draft1's and
  effect-draft2's operator sources are recorded as titles only ("Sep 29
  clarification…", "Operator discussion through September 29").
- **No synthesis exists** for the composition wave (no `draft-syn`) and no
  reconciliation doc between execution-model0 and the Sep 26 reopen.
- **Unknown-author files**: `design/install-context/systemd0.unknown.md`,
  `.design/config-user-target/{core-rescope0,assessment0,build0}.unknown.md`
  lack model suffixes; content is usable, provenance is partial.
- **Stale claims to distrust**: `.design/config-user-target/README.md` ("not
  been deployed" — false since Sep 13); any figure in
  config-anneal/use-cases1 (Sep 13 survey counts); assess0's live-deployment
  observations (dated; direction still accurate on-disk, but re-verify before
  acting); docs-survey0's own `stale_after: 2026-10-29` scope (pre-Oct work).
- **Not covered here by commission**: the running/completed Sol environment
  wave's scratch `.test-agent/cfr-environment/` is cited via its committed
  report only; the btrfs-backup, key-repeat, and other unrelated October
  design threads were skipped; the full implementation audit of every domain
  module is explicitly Astra's stage.

## Handoff for Astra medium (prioritized)

1. **Hold the whole ambition in view.** The reset = composable Effect-native
   runtime environment for domain modules with: annotated native
   contributions + default discovery + extensible init + mutable typed run
   data + durable history (draft2); BINS-first admission without parsing
   script internals (draft1 §2 table; opaque vs expanded rule); navigable
   specificity and visible identity (composition-problem0); material/
   exposure/placement and confext-build as the bold downstream test
   (composition-problem0; build-inputs1.fx for evidence); host-common
   bootstrap as a first-class design object. The Oct 12 environment work is
   the *entry slice*, not the destination; do not shrink the draft to ENV.
2. **Treat these as settled rulings, not proposals:** Effect as execution
   foundation (CFR scope); no completed backbone from the experiments; the
   retained-ideas list; the admission limits (no premature global graphs, no
   mandatory receipts, opaque leaves stay honest); three honest inspection
   levels; mutable collaboration is normal; equality is not reuse; executable
   location is not deployment identity; implementation provider ≠ deployment
   being operated on; systemd scope ≠ context; simplification.md's preserved
   product contracts.
3. **Treat these as open and decide with evidence:** program form (§1 above),
   registry-vs-ledger provenance, first substantive domain (config pipelines
   vs confext vs selected-environment), history/durability minimalism, and
   the discovery/bootstrap/sourcing unification (§2 above).
4. **Verify-before-inheriting:** world-map0 and docs-survey0 are dated
   (Sep 29); the shipped surface has since grown (definitions, ENV, actions,
   registry). Re-check `doc/config/README.md` + `definitions.md` +
   `doc/actions/README.md` when assessing feasibility against current code.
5. **Ground the draft in the shipped compatibility surface and the standing
   failure class:** six fixed commands + `config-` lane coexistence, the
   BINS adapter table, the dangling zim-main aliases — a credible reset
   explains its cutover for exactly these.
6. **Write the draft as a new independent wave** under
   `design/compfuzor-runtime/` (or `runtime-direction/`) with your own model
   suffix; previous waves are available context; do not modify the recovered
   docs. Name the deletion list and the first bounded checkpoint (draft2 §10's
   five demonstrations are the standing bar) plus what the operator must
   review before implementation (path semantics, phase grouping, invocation
   multiplicity, execution policy, material placement, bootstrap).

## Cross-references

- [Runtime direction index](/design/runtime-direction/index.md) — maintained
  reading map this report extends.
- [Recovered-docs survey](/design/runtime-direction/docs-survey0.glm53fx.md) —
  the Sep 29 predecessor recovery; five adoption meanings and the
  implementation-vs-intent snapshot.
- [Environment follow-up](/design/compfuzor-runtime/environment1.gpt61sol.md) —
  the completed same-day narrow probe (cited, not re-verified).
- [doc/config/log.md](/doc/config/log.md) — deployment evidence for every
  "shipped" claim in the table above.
