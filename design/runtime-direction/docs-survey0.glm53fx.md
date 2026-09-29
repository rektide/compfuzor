---
type: DocsSurvey
title: Prior intent and plans for the runtime/config/action/composition system
description: Navigation report over 2026-09-11..09-29 design docs and logs for resuming the compfuzor-runtime effort, focused on documented adoption mismatches and limits.
resource: /design/runtime-direction/docs-survey0.glm53fx.md
tags: [compfuzor, runtime, config, composition, adoption, catalog, flows, survey]
status: draft
generated: { by: 'model:zai/glm-5.3-flash-max', at: '2026-09-29' }
verified: { by: 'model:zai/glm-5.3-flash-max (source + on-disk inspection, no live runs)' }
stale_after: 2026-10-29
sources:
  - id: config-readme
    resource: /doc/config/README.md
    title: Maintained configuration entry point
  - id: execution-model
    resource: /design/config-anneal/execution-model0.gpt6.md
    title: Annealed contributor/flow/composition checkpoint
  - id: assess0
    resource: /design/compfuzor-runtime/assess0.glm53fm.md
    title: Sep 18 state of the runtime effort
  - id: lane-assessment
    resource: /design/runtime-config-lane/assessment0.gpt61sol.md
    title: Sep 29 apt-client config-lane alignment assessment
  - id: composition-brief
    resource: /design/compfuzor-runtime/composition-problem0.gpt6a.md
    title: Sep 26 composition problem brief
---

# Docs survey: prior intents for the runtime/config/action/composition system

## Situation and direction

The runtime effort (one multicall `compfuzor-runtime.mjs`, attributed read-only
catalog, opt-in flow execution) ran hot Sep 13–14, went dormant, and was
reopened Sep 26 by a composition/Effect wave that deliberately treated the
existing runtime as "barely used and unvetted" evidence rather than constraint
([composition-problem0.gpt6a.md L36-39](/design/compfuzor-runtime/composition-problem0.gpt6a.md)).
Today's apt-cacher `config` compositor lane (`ruzxvrsrrqkt`, `stktrklylmmn`)
and its alignment assessment
([assessment0.gpt61sol.md](/design/runtime-config-lane/assessment0.gpt61sol.md))
re-engaged the question of orchestration skew. The operator wants to resume the
runtime/config/composition direction and remembers "some design mismatches
around adoption that didn't make sense, limits". This report recovers the
intent/plan corpus, separates the distinct meanings of *adoption*, ranks a
reading route, and states implementation-versus-intent deltas with evidence.

Method: read of the orientation docs plus broad discovery across `doc/`,
`design/`, `.design/`, and `jj log`; verification by source inspection
(`runtime_catalog.py`, `bin_composers.py`, `flow/runtime.ts`,
`zim/activation.ts`) and read-only `ls`/`readlink` of live deployments. No
playbooks, tests, or mutations were run.

## First: "adoption" has five distinct meanings here

Do not conflate these; the corpus uses the word in all five senses:

1. **Adopting the new runtime layout into existing deployments** (upgrade of
   installed state). The live sore spot:
   [assess0.glm53fm.md §5](/design/compfuzor-runtime/assess0.glm53fm.md) —
   the Sep 18 `zim.opt.pb` failure, file→symlink refusal, no-prune collision.
   Still unresolved on disk today (below).
2. **Domains/playbooks adopting a shared contract** (second adopters of CONFIG
   contexts, of the selected-name resolver, of native composition). The
   documented mismatches: systemd was assessed and *rejected* as a second
   context adopter ([systemd0.unknown.md](/design/install-context/systemd0.unknown.md));
   `mcp-cli.src.pb` was slated as the second real context adopter and still
   has not adopted ([execution-model0.gpt6.md L598](/design/config-anneal/execution-model0.gpt6.md)).
3. **Admission of existing materials/programs into the new runtime** — whether
   legacy artifacts, build evidence, and opaque scripts must become
   CFR-produced/-receipted to be packageable/observable. The newest documented
   limits, from the Sep 26 experiments disposition and Effect draft: rejected
   constraints include mandatory receipts for legacy inputs and premature
   global graphs; opaque legacy operations remain honest leaves (details in
   section F below).
4. **Archive custody adoption** — a separate, older toolkit thread, distinct
   from deployment. The archive README's central boundary separates the two
   jobs: `deploy` maintains a deployment workspace; `adopt` + `verify-adoption`
   takes custody of another checkout's work "without switching either
   checkout" ([archive/README.md](/archive/README.md), "two related, but
   deliberately different, jobs"). What this session just shipped is the
   *deployment* side: narrow automatic conversion of a legacy deployment
   `repo` alias to the archive into a dedicated jj/Git workspace
   ([migration0.gpt61sol.md](/design/archive-deploy-layout/migration0.gpt61sol.md),
   commits `wytpmzzllwlz`..`wqtvrvqpqwto`, Sep 29). Custody adopt/verify is
   implemented but is not the deployment cutover.
5. **Library/adoption of Effect — runtime/CFR scope only.** The Sep 26
   direction choice ("The operator has chosen the Effect direction",
   [effect-draft0.gpt6a.md L39-40](/design/compfuzor-runtime/effect-draft0.gpt6a.md))
   concerns the compfuzor runtime/CFR backbone; nothing there is implemented.
   This is *not* a global statement: the archive toolkit CLI is already
   Effect4-implemented (e.g. `archive/src/cli/commands/verify-adoption.ts`,
   `health.ts`, `heal.ts` import `effect`), and its committed bundle is built
   by the same Vite+ config ([vite.config.ts](/vite.config.ts), second pack
   entry).

Given "we had some intents/plans that I think I'm missing … design mismatches
around adoption that didn't make sense, limits", readings 1–3 are the best
fit; 4 is shipped/separate; 5 is chosen-but-unstarted within CFR only.

## Ranked reading route

Primary — newest resumption intent first, then grounding:

1. [/design/compfuzor-runtime/composition-problem0.gpt6a.md](/design/compfuzor-runtime/composition-problem0.gpt6a.md) —
   the newest operator direction (Sep 26): navigable specificity, visible
   identity, early shared runtime on the table, design tests (L129-138), open
   decisions (L148-168). The existing runtime is evidence to assess, not
   constraint (L36-39).
2. [/design/compfuzor-runtime/experiments0.gpt6a.md](/design/compfuzor-runtime/experiments0.gpt6a.md) —
   the experiments disposition closing that wave (L169-229): "Reject a claim
   of a completed backbone"; recommended reinterpretation (registry describes,
   domain modules interpret, runner interprets inspectable programs); and the
   admission limits — "Avoid premature global task graphs, mandatory receipts
   for all legacy inputs, forced confext dependency on a fully
   project-contained layout" (L225-227); "Opaque legacy operations remain
   honest leaves" (L221).
3. [/design/compfuzor-runtime/effect-draft0.gpt6a.md](/design/compfuzor-runtime/effect-draft0.gpt6a.md) —
   the chosen CFR-on-Effect direction, not yet implemented. Key sections:
   "Data is not necessarily an instruction" and the three honest inspection
   levels (L134-208); placement/confext with "Reuse existing material by
   default" and "Do not require every legacy project to have been built by
   CFR merely to package its files" (L379-383); durable execution is a
   different question (L397-403).
4. [/design/compfuzor-runtime/assess0.glm53fm.md](/design/compfuzor-runtime/assess0.glm53fm.md) —
   Sep 18 grounding: effort philosophy, architecture map, the representation-
   migration failure (§5), tensions (§6), ranked unblocks (§7).
5. [/design/runtime-config-lane/assessment0.gpt61sol.md](/design/runtime-config-lane/assessment0.gpt61sol.md) —
   today's verdict on the apt-client lane: real skew, three meanings of
   "configuration", verified divergences (L80-139), two unauthorized scopes
   (L158-171).
6. [/doc/config/README.md](/doc/config/README.md) — maintained truth: fixed
   CONFIG commands vs the authored `config-` compositor lane, native flow
   coverage limits (L69-113), experiment posture (L110-119). Read alongside
   the two competing second-round composition drafts:
   [composition-draft1.glm53.md](/design/compfuzor-runtime/composition-draft1.glm53.md)
   (one registry, host `cfr`, declared exposures) and
   [composition-draft1.sxh.md](/design/compfuzor-runtime/composition-draft1.sxh.md)
   (host runtime over project-local route joins and publication ledgers).

Historical roadmap — reconcile with the above, do not implement from it:

7. [/design/config-anneal/execution-model0.gpt6.md](/design/config-anneal/execution-model0.gpt6.md) —
   the Sep 14 annealed checkpoint: contributors/attribution, composition
   declarations, flows/phases, execution policy, implementation matrix
   (L591-605). Treat as the historical roadmap whose implemented rows
   (attribution, catalog, flow opt-in) survive and whose unimplemented rows
   must be *reconciled with the Sep 26 direction* before any of them becomes
   a spec — the Sep 26 brief explicitly frees existing types, flow names, and
   schemas from being constraints (L36-39).
8. [/doc/config/simplification.md](/doc/config/simplification.md) — preserved
   product contracts (L32-46), the "do not merge into a universal plan"
   guardrail (L197-211), recommended order (L250-259). The deletion test
   still governs any registry ambition.

Supporting, load-bearing for specific claims:

9. [/design/install-context/systemd0.unknown.md](/design/install-context/systemd0.unknown.md) —
   the canonical shared-contract adoption-mismatch precedent and its
   do-not-generalize list (L501-510); plus
   [systemd-links0.solx.md](/design/install-context/systemd-links0.solx.md)
   "Why this is not context unification" (L124-135).
10. [/design/config-anneal/use-cases1.glm53.md](/design/config-anneal/use-cases1.glm53.md) —
    the adopter taxonomy (Sep 13 survey): six meanings of install (L273-297,
    "adoption" at L289), cheapest adopters (L250-257), tracer migrations
    (L440-467). Figures are historical survey counts, not today's.

## Intent/status chronology

| Date | Doc/commit | Kind | Status |
|---|---|---|---|
| Sep 11–13 | `.design/config-user-target/` builds 1–5 | inquiry→implementation | Consumer toolkit implemented; **live** since Sep 13 (its README claim "not been deployed" is stale) |
| Sep 13 | [command0.solx.md](/design/config-context/command0.solx.md) + [command0-review0.solx.md](/design/config-context/command0-review0.solx.md) | accepted instruction | Fixed six-command CONFIG surface; superseded details on stdout/bypass/aggregate status only |
| Sep 13 | [doc/config/simplification.md](/doc/config/simplification.md) | plan (draft) | Items 2,3,6 done; item 1 (Zim envsubst deletion) **not** done; item 4 (spec overlap) deliberately deferred |
| Sep 13 | [systemd0.unknown.md](/design/install-context/systemd0.unknown.md) | accepted verdict | "Do not adopt `resolveSelectedName` in systemd"; scope ≠ context |
| Sep 13 | [systemd-links0.solx.md](/design/install-context/systemd-links0.solx.md) (+review) | implemented | LINKS v2 `strategies`/`compose`; documented current in [doc/subsys.md L505-632](/doc/subsys.md) |
| Sep 13–14 | [execution-model0.gpt6.md](/design/config-anneal/execution-model0.gpt6.md) | annealed checkpoint — **historical roadmap** since the Sep 26 reopen | Partially implemented (next section); unimplemented rows need reconciliation, not direct execution |
| Sep 14 | [doc/config/log.md L38-109](/doc/config/log.md) | implemented | Attribution + read-only catalog + indexed workflows; direct final CONFIG compile (delete `_internalize_config_bins`); opt-in flow execution behind `RUNTIME_FLOW_EXECUTION` with containment hardening; zim2/mise2 contained experiments |
| Sep 18 | [assess0.glm53fm.md](/design/compfuzor-runtime/assess0.glm53fm.md) | assessment | Dormancy + zim-main file→symlink failure; remediations proposed, only partially executed |
| Sep 19 | [zim-pieces0.glm53m.md](/design/compfuzor-runtime/zim-pieces0.glm53m.md) | decided posture | no-`/opt`-startup; `runtime_bundles.py` role clarified |
| Sep 26 | [log.md L3-36](/doc/config/log.md) | implemented (live) | mcp-cli portable MCP records + placement; **not** a context adoption (still canonical CONFIGS) |
| Sep 26 | [composition-problem0.gpt6a.md](/design/compfuzor-runtime/composition-problem0.gpt6a.md) + [draft0.gpt6a](/design/compfuzor-runtime/composition-draft0.gpt6a.md) / [draft1.glm53](/design/compfuzor-runtime/composition-draft1.glm53.md) / [draft1.sxh](/design/compfuzor-runtime/composition-draft1.sxh.md) | inquiry wave, **no synthesis** | Competing registry/route-join designs; runtime free to change |
| Sep 26 | [experiments0.gpt6a.md](/design/compfuzor-runtime/experiments0.gpt6a.md) (+experiment1-4) | experiments, closed | "Reject a claim of a completed backbone" (L197-201); admission limits set: no premature graphs, no mandatory receipts for legacy inputs, opaque legacy operations remain honest leaves (L181-229); ideas retained, no fifth probe authorized |
| Sep 26 | [effect-draft0.gpt6a.md](/design/compfuzor-runtime/effect-draft0.gpt6a.md) | proposed architecture (CFR scope only) | "The operator has chosen the Effect direction" (L39-40); interfaces still reviewable; nothing implemented in the compfuzor runtime — the archive toolkit CLI is separately already Effect4 (see meaning 5) |
| Sep 27–29 | [archive-migration/](/design/archive-migration/brief0.gpt6sol.md), [archive-workspace/](/design/archive-workspace/direction0.gpt6astra.md), [archive-deploy-layout/](/design/archive-deploy-layout/migration0.gpt61sol.md) | implemented + verified | Narrow archive-alias → dedicated workspace migration shipped (meaning 3) |
| Sep 29 | `dd0d9a07`, `4ff3de4b`; [assessment0.gpt61sol.md](/design/runtime-config-lane/assessment0.gpt61sol.md) | implemented + draft assessment | `config` compositor action + apt client snippet lane; alignment assessment, neither follow-up scope authorized |

Nothing in `design/` is an accepted runner authority: generated shell
compositors remain execution authority; the catalog is read-only unless a
deployment opts into experimental flow execution
([doc/config/README.md L105-113](/doc/config/README.md)).

## The documented adoption mismatches and limits

### A. Shared-contract adoption mismatches (meaning 2)

- **systemd scope is not a CONFIG context.** The Sep 13 comparison concluded
  the natural systemd key is `(scope, unit identity)`, rejected Option C
  (context-selected `install-systemd.sh`) outright, and kept hard system/user
  aggregates because a context "grants no authority"
  ([systemd0.unknown.md L36-71, L445, L501-510](/design/install-context/systemd0.unknown.md)).
  Counterexample preserved on purpose: sharing copy/link delivery via LINKS v2
  does **not** make systemd a context
  ([systemd-links0.solx.md L124-135](/design/install-context/systemd-links0.solx.md)).
  Limit articulated: "Do not extract a universal install plan unless that
  comparison finds matching inputs, failures, ordering, and recovery
  semantics" ([command0.solx.md L265-266](/design/config-context/command0.solx.md)).
- **`CONFIG_INSTALL_OWNER` is a scalar, not a registry.** "Another
  complete-install adopter must choose a distinct value and validate its own
  ownership" — flagged as a remaining risk, not a designed extension point
  ([command0.solx.md L244-247](/design/config-context/command0.solx.md)).
- **The second context adopter never landed.** The matrix row "Native CONFIG
  context adoption in `mcp-cli.src.pb` — second real context adopter"
  ([execution-model0.gpt6.md L598](/design/config-anneal/execution-model0.gpt6.md))
  derives from use-cases1's tracer 2 (hand `ln -s` → `config-publish.sh
  --strategy link` under a declared user context,
  [use-cases1.glm53.md L448-452](/design/config-anneal/use-cases1.glm53.md)).
  Verified today: `mcp-cli.src.pb` declares canonical `CONFIGS` with no
  `CONFIG_CONTEXTS`, and `install-user.sh` still hand-links
  (`mcp-cli.src.pb L7-34`); only `zim.opt.pb`/`zim2.opt.pb` declare
  `CONFIG_CONTEXTS`. The Sep 26 mcp-cli migration modernized record format,
  not context adoption.
- **Adopter scarcity was quantified (Sep 13 survey figures, not current).**
  `CONFIGS` 9 playbooks (8 context-free), `CONFIG_CONTEXTS` 1, `LINKS` 34 of
  772; the ordinary majority is hand
  `ln -sfv` ([use-cases1.glm53.md L50-84, L325-337](/design/config-anneal/use-cases1.glm53.md)).
  Cheapest undeclared adopters: screen/clickpad/locales/interception-tools
  (L250-257, L492-494). A "dovecot-class" adoption vocabulary (adopt distro
  state, whole-file replacement, line-level merge) is named as a finish-line
  family, not started (L469-472).

### B. Runtime adoption of existing deployments (meaning 1)

- **Representation migration has no story.** The multicall unification flipped
  `bin/links/links.mjs` and `bin/zim/install.mjs` from raw-copy claims to
  symlink claims; `bins_link.tasks` has no `force`, so file→symlink conversion
  fails, and the no-prune constitution forbids silent cleanup. "The playbook
  declares the symlink but has no mechanism to disown the predecessor file";
  `BINS_ABSENT` named as the existing mechanism
  ([assess0.glm53fm.md L124-178, L182-185](/design/compfuzor-runtime/assess0.glm53fm.md)).
  This is the documented mismatch that "didn't make sense": a no-force +
  no-prune pairing makes the delivery-model cutover unadoptable by exactly the
  deployments that already exist.
- **Live evidence today (observed, read-only):** `/opt/zim-main/bin/zim/` and
  `/opt/zim-main/bin/links/` are now *empty* directories (stale real files
  removed ~Sep 18 17:09), but the alias claims were never re-rendered:
  `bin/zim/` is empty, `bin/config/` holds only the old shell
  `run.sh`/`processor.sh`/`toggle.sh` (no `command.mjs`), `config-remote.mjs`
  is absent, and the six fixed commands still target
  `config/command.mjs` — e.g. `config-install.sh → /opt/zim-main/bin/config/command.mjs`,
  a dangling symlink. `links.mjs → compfuzor-runtime.mjs` is fine. Precise
  classification (parent-verified, no operation run): the deployed **CONFIG
  command surface is incomplete** — fixed-command aliases dangle through the
  missing `config/command.mjs` and `bin/zim/` lost its alias target. This is
  not evidence of a general production shell outage; nothing was executed
  against the deployment. Assess0's ranked remediation #1 (deliberate
  `BINS_ABSENT` + re-render) is still the pending move.
- **Catalog-without-reader half-state** (`/opt/mise-main` gets catalog data
  with no runtime bins) — unresolved gate question
  ([assess0.glm53fm.md L189-191](/design/compfuzor-runtime/assess0.glm53fm.md)).
- **Experiment twins drift** — zim2/mise2 duplicate ~300 lines of module
  declarations; "zim2" naming misleads (L192-198).

### C. Lane/flow adoption mismatches (the Sep 29 skew)

- **Action/flow sets diverged.** `bin_composers.py` now recognizes `config`
  (L22) while `runtime_catalog.py` `_ACTION`/`_ROOT` and `flows` still know
  only build/install/apply-as-action and build/install/status-as-flow
  (L16-17, L251); `flow/runtime.ts` validates the same three verbs
  (L58). The config lane's leaves are commands, not native invocations:
  "Command inventory is not equivalent to native execution support"
  ([assessment0.gpt61sol.md L80-113](/design/runtime-config-lane/assessment0.gpt61sol.md)).
- **Arguments differ, not just names.** The lane forwards operator argv
  (`config.sh HOST...`); native flows execute descriptor-fixed `invoke.args`
  with no operator-argument forwarding (L115-127). Teaching three allowlists a
  fourth name would not converge anything.
- **Namespace coexistence is by construction, not by shared contract.** The
  fixed CONFIG commands ride `compose: false`/`action: install` exceptions;
  "the shared prefix does not imply a shared implementation or argument
  contract" ([doc/config/README.md L69-97](/doc/config/README.md)). The lane
  grows filename-grammar responsibility that execution-model0 intended to
  retire ("The evaluator matches target identity rather than deriving policy
  from an executable filename", execution-model0 L484-485).
- **Same mismatch predates config:** `apply` is an action with two users and
  no flow; a composed `apply.sh` would be silently skipped for flows
  ([apply-flow0.glm53.md L75-99](/design/compfuzor-runtime/apply-flow0.glm53.md)).

### D. What the Sep 14 matrix planned that has not happened

The matrix rows below are the historical roadmap: implemented rows survive;
unimplemented rows must be reconciled with the Sep 26 composition/Effect
direction before any of them is treated as the next implementation spec
(the Sep 26 brief frees existing types, flow names, and schemas from being
constraints, [composition-problem0.gpt6a.md L36-39](/design/compfuzor-runtime/composition-problem0.gpt6a.md)).

Matrix rows still open
([execution-model0.gpt6.md L591-605](/design/config-anneal/execution-model0.gpt6.md)):
authored `composition:` declarations (none exist — verified: no
`composition` handling in `runtime_catalog.py`/`bin_composers.py`; compiled
invocations are synthesized legacy lifts, cf. zim2's `legacy:*` workflow
files), native composition for global-bin LINKS, native composition for
systemd/Zim, managed-block provider pilots + Zim envsubst deletion
(`@@ZIM_*@@` engine still present, `files/zim/activation.ts` L135-141), new
flow execution authority (no live flow-driven run recorded — assess0 tension
6),
Effect retyping, spec consolidation (deliberately deferred). Done since the
matrix: attribution, read-only catalog, direct final CONFIG compile, opt-in
flow execution with hardened containment
([doc/config/log.md 2026-09-14](/doc/config/log.md)). On flow execution: the
corpus records only contained dry-runs and safe-install/status exercises;
no live flow-driven deployment run is recorded in the surveyed documents
(an absence of recorded evidence, not a proven universal negative — assess0
tension 6 asks for exactly that first live validation).

### E. The Sep 26 reopen: adoption of a *host-common* runtime (new limits opened)

[composition-problem0.gpt6a.md L63-93](/design/compfuzor-runtime/composition-problem0.gpt6a.md):
operator willing to drop per-deployment runtime distribution; bootstrap
ordering, version compatibility, missing-runtime behavior, and
"runtime location must not be confused with the deployment being operated on"
are explicitly required before any host-common `cfr`. The two draft1s disagree
productively on mechanism (registry projections vs route joins/publication
ledgers) but agree on: identity declared not parsed, plans before execution,
manual apply stays manual. Lifecycle limits are new first-class constraints:
confext is "a projection problem before it is a new flow name", pre-write
storage preparation "is a precondition, not a post-build action"
([runtime0.sm.md L125-156](/design/confext/runtime0.sm.md)); a project-local
runtime cannot prepare its own project
([composition-draft0.gpt6a.md L241-244](/design/compfuzor-runtime/composition-draft0.gpt6a.md)).

### F. Admission of existing materials/programs (meaning 3 — the likely remembered "limits")

The Sep 26 wave closes with explicit constraints on what the new runtime may
*demand* of existing state. These are adoption limits in the precise sense:
they bound how far "join the registry" can be made a precondition.

- **No completed backbone claim.** The four-experiment sequence is closed:
  "Reject a claim of a completed backbone: experiment 4 is a small dependency
  binding/registration mechanism and async dispatcher… its program
  descriptions do not describe executable composition before execution"
  ([experiments0.gpt6a.md L197-201](/design/compfuzor-runtime/experiments0.gpt6a.md)).
  Useful ideas are retained as architectural evidence (L181-204), not as an
  integrated architecture.
- **Rejected constraints (exact list).** "Avoid premature global task graphs,
  mandatory receipts for all legacy inputs, forced confext dependency on a
  fully project-contained layout, and a new round of toy experiments by
  default" ([experiments0.gpt6a.md L225-227](/design/compfuzor-runtime/experiments0.gpt6a.md)).
  This directly rejects reading "persisted realization evidence" as requiring
  that "every legacy material must first acquire a CFR-owned receipt"
  (L191-193).
- **Existing build evidence is admissible.** "Reuse existing material by
  default in `build/confext`. An explicit larger build program can first
  request realization, but packaging does not secretly regenerate. A material
  service may use durable receipts **or an adapter over existing build
  evidence**. Do not require every legacy project to have been built by CFR
  merely to package its files. Describe what is known versus assumed by each
  adapter" ([effect-draft0.gpt6a.md L379-383](/design/compfuzor-runtime/effect-draft0.gpt6a.md)).
- **Opaque legacy programs stay honest leaves.** "Dynamic continuation may
  expose only a known prefix before execution; display that boundary rather
  than pretending to know future work. Opaque legacy operations remain honest
  leaves" ([experiments0.gpt6a.md L219-221](/design/compfuzor-runtime/experiments0.gpt6a.md)).
  The Effect draft sharpens the inspection epistemology: an `Effect.gen` body
  "does not automatically acquire an inspectable sequence from its source
  text"; authored outlines "must be labeled accordingly"; "No speculative
  dry-run of a generator with invented return values"; and inspection has
  three honest levels — catalog, resolved plan (exact for explicit
  structures, dynamic/opaque sections marked), execution trace — where "no
  one level masquerades as another"
  ([effect-draft0.gpt6a.md L147-207](/design/compfuzor-runtime/effect-draft0.gpt6a.md)).
  The sxh draft agrees from the data side: lift `ETC_FILES`/`links.json` into
  ledgers only under stated conditions, and "Use `links.json` as
  compatibility mapping evidence, not a magic complete package manifest"
  ([composition-draft1.sxh.md L289-302](/design/compfuzor-runtime/composition-draft1.sxh.md));
  a hand-authored monolithic `apply.sh` is "one opaque action until split;
  do not mislabel it a composed root" (L394-395).
- **Counterexamples preserved.** Receipts are permitted, not banned — "This
  does not establish that every legacy material must first acquire a
  CFR-owned receipt" cuts both ways: adapters may *use* receipts where they
  exist. And legacy BINS participation is retained in every draft (glm53
  draft1 keeps BINS authoring as the input format with the adapter as "the
  only filename parser left",
  [composition-draft1.glm53.md L191-196, L433](/design/compfuzor-runtime/composition-draft1.glm53.md)).

So the limit is symmetric: the new system must admit existing bytes, build
evidence, and opaque scripts without forcing them through CFR production or a
project schema — and must label what it knows versus assumes rather than
pretending static inspection of dynamic/opaque programs.

## Contradictions and tensions to carry forward

1. **Sep 14 anneal vs Sep 26 reopen.** execution-model0 fixed a vocabulary
   (contributors/invocations/NN-FLOW-SLUG files) that composition-problem0
   declares "evidence to assess, not constraints that must survive". No
   synthesis reconciles them; the drafts each *cite* execution-model0 while
   replacing its compiled-layer mechanics. Per the operator's resumption
   priority, the Sep 26 brief + experiments disposition + effect-draft0 are
   the newest intent; the matrix is the historical roadmap to reconcile.
   Resuming without that reconciliation risks implementing against a
   superseded schema.
2. **No-prune + no-force vs migration.** A constitution-level posture
   collides with delivery-model cutovers; assess0 names the gap and the
   mechanism (`BINS_ABSENT`) but no policy doc exists. This bit production
   (zim-main) and remains unfixed.
3. **Filename grammar vs declared identity.** The new `config` lane deepens
   name-derived composition the anneal wanted to retire; today's assessment
   frames the consequential decision as *domain action vs aggregate flow*,
   explicitly not which language executes the leaf
   ([assessment0.gpt61sol.md L168-171](/design/runtime-config-lane/assessment0.gpt61sol.md)).
4. **Simplification guardrails vs registry ambition.** simplification.md says
   delete layers, don't add frameworks, defer spec consolidation; the Sep 26
   drafts propose substantial new registries/ledgers. Both agree on the
   deletion test; the tension is sequencing (delete first vs design first).
5. **Inspectable descriptions vs opaque legacy programs.** The new designs
   want plans and explanations; legacy scripts and `Effect.gen` bodies are
   not statically inspectable. The Sep 26 resolution — three honest
   inspection levels, known-prefix boundaries, opaque leaves — must be kept
   against the pull to fake static plans for dynamic programs
   ([effect-draft0.gpt6a.md L147-207](/design/compfuzor-runtime/effect-draft0.gpt6a.md)).
6. **Stale entry points.** `.design/config-user-target/README.md` still says
   the toolkit "has not been deployed"; `doc/config/README.md` correctly
   postdates it. Trust `doc/` over `.design/` claims.

Notable absences: no `draft-syn` synthesis for the composition wave; no
representation-migration policy; no native config/apply flow decision; no
reconciliation of `install` render-time vs operator-time semantics beyond
use-cases1's phase-dimension finding; no live flow-execution run is recorded
anywhere in the corpus (absence of recorded evidence, not a proven
comprehensive negative).

## Implementation vs intent (verified snapshot)

| Intent | State | Evidence |
|---|---|---|
| Omnibus multicall runtime + alias dispatch | Done | Current checked-in artifact is `runtime/compfuzor-runtime.mjs` (Vite+ `outDir: "runtime"`, [vite.config.ts](/vite.config.ts); rebuilt Sep 29). A stale `build/runtime/compfuzor-runtime.mjs` (Sep 22) also remains checked in — the `build/runtime/…` paths cited in the Sep 13/14 log and assess0 are historical |
| Attribution + read-only catalog + indexed workflows | Done | `runtime_catalog.py`; [log.md L77-109](/doc/config/log.md) |
| Direct final CONFIG compilation | Done | [log.md L102-105](/doc/config/log.md) |
| Opt-in flow execution (build/install/status only) | Done, contained-dry-run only | `flow/runtime.ts` L58; assess0 tension 6 |
| Authored `composition:` declarations | Absent | no code path; `legacy:*` synthesized invocations only |
| Global-bin LINKS / systemd / Zim native composition | Absent | matrix rows open |
| Zim envsubst deletion via block-in-file | Absent | `@@ZIM_*@@` in `activation.ts` |
| mcp-cli second CONFIG context adopter | Absent | `mcp-cli.src.pb` has no `CONFIG_CONTEXTS` |
| `config` compositor action + apt snippet lane | Done today | `bin_composers.py` L22; `4ff3de4b` |
| Native config-flow projection | Absent | [assessment0.gpt61sol.md L94-113](/design/runtime-config-lane/assessment0.gpt61sol.md) |
| Host-common `cfr` bootstrap | Not started | verified free on PATH Sep 26; nothing since |
| Effect foundation (CFR/runtime scope) | Chosen, not implemented | [effect-draft0.gpt6a.md §1](/design/compfuzor-runtime/effect-draft0.gpt6a.md); archive toolkit CLI already Effect4-implemented separately (`archive/src/cli/commands/*.ts`) |
| Admission of legacy materials without CFR receipts | Design posture recorded, not implemented | [experiments0.gpt6a.md L181-229](/design/compfuzor-runtime/experiments0.gpt6a.md); [effect-draft0.gpt6a.md L379-383](/design/compfuzor-runtime/effect-draft0.gpt6a.md) |
| Deployment-alias → archive-workspace cutover | Implemented + verified (deployment side only; archive *custody* `adopt`/`verify-adoption` is a separate, pre-existing toolkit surface) | `wqtvrvqpqwto` etc., Sep 29; [migration0.gpt61sol.md](/design/archive-deploy-layout/migration0.gpt61sol.md); [archive/README.md](/archive/README.md) two-job boundary |

## Open consequential decisions and plausible next slices

Decisions the docs mark as open and consequential (no timeframes):

1. **Domain action vs aggregate flow** for configuration generation (and by
   extension `apply`): the apt-lane question
   ([assessment0.gpt61sol.md L158-171](/design/runtime-config-lane/assessment0.gpt61sol.md)).
   Compatibility-only vs runtime-convergence are the two authorized-candidate
   scopes; neither chosen.
2. **Does the flows schema survive?** apply-flow0 Idea B (3-line apply-flow
   patch) is "motion or waste" depending on this
   ([apply-flow0.glm53.md L152-156](/design/compfuzor-runtime/apply-flow0.glm53.md)).
3. **Which composition draft shape, if any**: one compiled registry with
   projections (glm53 draft1) vs host runtime over route joins + publication
   ledgers (sxh draft1); plus the eight unresolved registry choices
   ([composition-draft1.glm53.md L472-488](/design/compfuzor-runtime/composition-draft1.glm53.md))
   and six review gates
   ([composition-draft1.sxh.md L424-445](/design/compfuzor-runtime/composition-draft1.sxh.md)).
4. **Host-common runtime bootstrap** (tracked as
   `compfuzor-runtime-bootstrap`): bootstrap ordering, versioning,
   missing-runtime behavior ([composition-problem0.gpt6a.md L73-82](/design/compfuzor-runtime/composition-problem0.gpt6a.md)).
5. **Representation-migration policy** for existing deployments (force vs
   `BINS_ABSENT` declaration vs one-shot remediation) — assess0 tension 1.
6. **Admission contract for existing materials/programs**: how adapters
   describe known-versus-assumed evidence, when receipts are used vs optional,
   and how dynamic/opaque sections are marked in resolved plans — effect-draft0
   L379-383 + L147-207 and experiments0 L181-229 set the constraints; the
   concrete adapter contract is undecided.

Plausible coherent slices, each grounded in a doc's own recommendation:

- **Repair-first:** finish assess0 remediation #1 (declare the four stale
  paths `BINS_ABSENT` in `zim.opt.pb`, re-render, verify the fixed-command
  aliases resolve again), then rehearse the zim2 cutover (assess0 #2/#3).
  Restores the incomplete CONFIG command surface and retires the recurring
  failure class before any design work rides on it.
- **Synthesis wave:** one `draft-syn`-style reconciliation of execution-model0
  + the three composition drafts + effect-draft0, producing a single current
  intent doc — the missing piece for everything downstream.
- **Smallest honest adopter:** land mcp-cli as the second `CONFIG_CONTEXTS`
  declarer (`config-publish.sh --strategy link` replacing the hand `ln`),
  closing the oldest open matrix row and giving contexts a non-Zim adopter.
- **Config-lane decision:** pick compatibility-only (label the lane outside
  native flows; stop orchestration growth) or runtime-convergence (define the
  operator-input contract + one shared description); do not merely add `config`
  to three allowlists.

## Cross-references

- [/archive/README.md](/archive/README.md) — the archive toolkit's central
  boundary: keeping work, using work, publishing work, and retiring an old
  location are different decisions; `deploy` (deployment workspace) vs
  `adopt`+`verify-adoption` (custody). Grounds the meaning-4 separation.
- [/doc/config/consumer-toolkit.md](/doc/config/consumer-toolkit.md) — the
  behavioral contract any runtime rework must preserve; source of the
  copy/link/context semantics cited throughout.
- [/doc/subsys.md](/doc/subsys.md) — current BINS/LINKS/compositor behavior
  the catalog and any registry must lift; documents LINKS v2 and the
  `config` lane's legacy execution (L354-413).
- [/design/config-anneal/flow-execution-review0.gpt6.md](/design/config-anneal/flow-execution-review0.gpt6.md) —
  the flow-execution hardening history and its final "multicall-safe
  containment" gate (addenda, L226-395).
- [/design/confext/runtime0.sm.md](/design/confext/runtime0.sm.md) — verified
  runtime limits table (L88-110) and "incremental first, remake conditional"
  opinion (L158-192); the counterweight to the bolder drafts.
- [/design/compfuzor-runtime/effect-design0.glm53.md](/design/config-anneal/effect-design0.glm53.md) —
  the Sep 14 Effect mapping ("deliberate non-adoption of durable workflow
  machinery"), predecessor to effect-draft0.
- [/design/archive-deploy-layout/verification0.gpt61sol.md](/design/archive-deploy-layout/verification0.gpt61sol.md) —
  the completed meaning-3 adoption, for contrast on what "adoption done
  right" looked like (narrow scope, guarded recovery, verification).
- [/design/vars-precedence/](/design/vars-precedence) — adjacent current
  inquiry into `common.yaml` loading; touches the same authoring surface.

## Resumption prompt

> Resume the compfuzor runtime/composition effort from the newest intent:
> /design/compfuzor-runtime/composition-problem0.gpt6a.md, the experiments
> disposition in /design/compfuzor-runtime/experiments0.gpt6a.md (L169-229:
> no completed backbone; no premature graphs; no mandatory receipts for
> legacy inputs; opaque legacy operations stay honest leaves), and
> /design/compfuzor-runtime/effect-draft0.gpt6a.md (chosen CFR-on-Effect
> direction; three honest inspection levels; reuse existing material by
> default). Treat /design/config-anneal/execution-model0.gpt6.md and its
> matrix as the historical roadmap to reconcile, not the next implementation
> spec. Distinguish five adoption meanings: (1) upgrading existing
> deployments to the runtime layout — zim-main's CONFIG command surface is
> incomplete (dangling fixed-command aliases; assess0 §5); (2) second
> adopters of shared contracts (systemd rejected; mcp-cli still open);
> (3) admission of existing materials/programs — adapters over existing
> build evidence, receipts optional, known-vs-assumed labeled; (4) archive
> custody adoption (adopt/verify-adoption) is a separate toolkit thread from
> the deployment-alias→workspace cutover that just shipped; (5) Effect
> adoption is CFR/runtime-scoped — the archive CLI is already Effect4. Do
> not add `config`/`apply` to flow allowlists until the
> domain-action-vs-flow and flows-schema-survival decisions are made, and do
> not require CFR production of legacy materials merely to package or
> observe them.
