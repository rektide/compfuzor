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
([composition-problem0.gpt6a.md L36-39](/design/compfuzor-runtime/composition-problem0.gpt6.md)).
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

## First: "adoption" has four distinct meanings here

Do not conflate these; the docs use the word in all four senses:

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
3. **Archive custody adoption** — deployment `repo` symlinks to an archive
   being converted into dedicated jj/Git workspaces. Recently *implemented and
   verified* ([migration0.gpt61sol.md](/design/archive-deploy-layout/migration0.gpt61sol.md),
   commits `wytpmzzllwlz`..`wqtvrvqpqwto`, Sep 29). A separate, mostly
   finished thread; not the runtime mismatch.
4. **Library/adoption of Effect** ("Effect retyping and CLI adoption",
   [execution-model0.gpt6.md L602](/design/config-anneal/execution-model0.gpt6.md));
   direction chosen Sep 26 ([effect-draft0.gpt6a.md §1](/design/compfuzor-runtime/effect-draft0.gpt6a.md)),
   nothing implemented.

Given "we had some intents/plans that I think I'm missing … design mismatches
around adoption that didn't make sense, limits", readings 1 and 2 are the best
fit; 3 is done, 4 is chosen-but-unstarted.

## Ranked reading route

Primary (read in this order):

1. [/doc/config/README.md](/doc/config/README.md) — maintained truth: fixed
   CONFIG commands vs the authored `config-` compositor lane, native flow
   coverage limits (L69-113), experiment posture (L110-119).
2. [/design/config-anneal/execution-model0.gpt6.md](/design/config-anneal/execution-model0.gpt6.md) —
   the annealed intent: contributors/attribution, composition declarations,
   flows/phases, execution policy, and the implementation matrix with status
   per row (L591-605).
3. [/design/compfuzor-runtime/assess0.glm53fm.md](/design/compfuzor-runtime/assess0.glm53fm.md) —
   Sep 18 grounding: effort philosophy, architecture map, the representation-
   migration failure (§5), tensions (§6), ranked unblocks (§7).
4. [/design/runtime-config-lane/assessment0.gpt61sol.md](/design/runtime-config-lane/assessment0.gpt61sol.md) —
   today's verdict on the apt-client lane: real skew, three meanings of
   "configuration", verified divergences (L80-139), two unauthorized scopes
   (L158-171).
5. [/design/compfuzor-runtime/composition-problem0.gpt6a.md](/design/compfuzor-runtime/composition-problem0.gpt6a.md) —
   the newest operator direction: navigable specificity, visible identity,
   early shared runtime on the table, design tests (L129-138), open decisions
   (L148-168). Then its two competing second-round drafts:
   [composition-draft1.glm53.md](/design/compfuzor-runtime/composition-draft1.glm53.md)
   (one registry, host `cfr`, declared exposures) and
   [composition-draft1.sxh.md](/design/compfuzor-runtime/composition-draft1.sxh.md)
   (host runtime over project-local route joins and publication ledgers).

Supporting, load-bearing for specific claims:

6. [/doc/config/simplification.md](/doc/config/simplification.md) — preserved
   product contracts (L32-46), the "do not merge into a universal plan"
   guardrail (L197-211), recommended order (L250-259).
7. [/design/install-context/systemd0.unknown.md](/design/install-context/systemd0.unknown.md) —
   the canonical adoption-mismatch precedent and its do-not-generalize list
   (L501-510); plus [systemd-links0.solx.md](/design/install-context/systemd-links0.solx.md)
   "Why this is not context unification" (L124-135).
8. [/design/config-anneal/use-cases1.glm53.md](/design/config-anneal/use-cases1.glm53.md) —
   the adopter taxonomy: six meanings of install (L273-297, "adoption" at
   L289), cheapest adopters (L250-257), tracer migrations (L440-467).

## Intent/status chronology

| Date | Doc/commit | Kind | Status |
|---|---|---|---|
| Sep 11–13 | `.design/config-user-target/` builds 1–5 | inquiry→implementation | Consumer toolkit implemented; **live** since Sep 13 (its README claim "not been deployed" is stale) |
| Sep 13 | [command0.solx.md](/design/config-context/command0.solx.md) + [command0-review0.solx.md](/design/config-context/command0-review0.solx.md) | accepted instruction | Fixed six-command CONFIG surface; superseded details on stdout/bypass/aggregate status only |
| Sep 13 | [doc/config/simplification.md](/doc/config/simplification.md) | plan (draft) | Items 2,3,6 done; item 1 (Zim envsubst deletion) **not** done; item 4 (spec overlap) deliberately deferred |
| Sep 13 | [systemd0.unknown.md](/design/install-context/systemd0.unknown.md) | accepted verdict | "Do not adopt `resolveSelectedName` in systemd"; scope ≠ context |
| Sep 13 | [systemd-links0.solx.md](/design/install-context/systemd-links0.solx.md) (+review) | implemented | LINKS v2 `strategies`/`compose`; documented current in [doc/subsys.md L505-632](/doc/subsys.md) |
| Sep 13–14 | [execution-model0.gpt6.md](/design/config-anneal/execution-model0.gpt6.md) | annealed checkpoint (direction, not runner authority) | Partially implemented (next section) |
| Sep 14 | [doc/config/log.md L38-109](/doc/config/log.md) | implemented | Attribution + read-only catalog + indexed workflows; direct final CONFIG compile (delete `_internalize_config_bins`); opt-in flow execution behind `RUNTIME_FLOW_EXECUTION` with containment hardening; zim2/mise2 contained experiments |
| Sep 18 | [assess0.glm53fm.md](/design/compfuzor-runtime/assess0.glm53fm.md) | assessment | Dormancy + zim-main file→symlink failure; remediations proposed, only partially executed |
| Sep 19 | [zim-pieces0.glm53m.md](/design/compfuzor-runtime/zim-pieces0.glm53m.md) | decided posture | no-`/opt`-startup; `runtime_bundles.py` role clarified |
| Sep 26 | [log.md L3-36](/doc/config/log.md) | implemented (live) | mcp-cli portable MCP records + placement; **not** a context adoption (still canonical CONFIGS) |
| Sep 26 | [composition-problem0.gpt6a.md](/design/compfuzor-runtime/composition-problem0.gpt6a.md) + [draft0.gpt6a](/design/compfuzor-runtime/composition-draft0.gpt6a.md) / [draft1.glm53](/design/compfuzor-runtime/composition-draft1.glm53.md) / [draft1.sxh](/design/compfuzor-runtime/composition-draft1.sxh.md) | inquiry wave, **no synthesis** | Competing registry/route-join designs; runtime free to change |
| Sep 26 | [experiments0.gpt6a.md](/design/compfuzor-runtime/experiments0.gpt6a.md) (+experiment1-4) | experiments, closed | "Reject a claim of a completed backbone" (L169-192); ideas retained, no fifth probe authorized |
| Sep 26 | [effect-draft0.gpt6a.md](/design/compfuzor-runtime/effect-draft0.gpt6a.md) | proposed architecture | "The operator has chosen the Effect direction" (L38); interfaces still reviewable; nothing implemented |
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
- **Adopter scarcity is quantified.** `CONFIGS` 9 playbooks (8 context-free),
  `CONFIG_CONTEXTS` 1, `LINKS` 34 of 772; the ordinary majority is hand
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
  a dangling symlink. `links.mjs → compfuzor-runtime.mjs` is fine. Production
  Zim is mid-migration and its CONFIG surface is currently broken; assess0's
  ranked remediation #1 (deliberate `BINS_ABSENT` + re-render) is still the
  pending move. (I did not run anything; verify before acting.)
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

### D. What execution-model0 planned that has not happened

Matrix rows still open
([execution-model0.gpt6.md L591-605](/design/config-anneal/execution-model0.gpt6.md)):
authored `composition:` declarations (none exist — verified: no
`composition` handling in `runtime_catalog.py`/`bin_composers.py`; compiled
invocations are synthesized legacy lifts, cf. zim2's `legacy:*` workflow
files), native composition for global-bin LINKS, native composition for
systemd/Zim, managed-block provider pilots + Zim envsubst deletion
(`@@ZIM_*@@` engine still present, `files/zim/activation.ts` L135-141), new
flow execution authority (never driven a real deployment — assess0 tension 6),
Effect retyping, spec consolidation (deliberately deferred). Done since the
matrix: attribution, read-only catalog, direct final CONFIG compile, opt-in
flow execution with hardened containment
([doc/config/log.md 2026-09-14](/doc/config/log.md)).

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

## Contradictions and tensions to carry forward

1. **Sep 14 anneal vs Sep 26 reopen.** execution-model0 fixed a vocabulary
   (contributors/invocations/NN-FLOW-SLUG files) that composition-problem0
   declares "evidence to assess, not constraints that must survive". No
   synthesis reconciles them; the drafts each *cite* execution-model0 while
   replacing its compiled-layer mechanics. Resuming without a synthesis risks
   implementing against a superseded schema.
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
5. **Stale entry points.** `.design/config-user-target/README.md` still says
   the toolkit "has not been deployed"; `doc/config/README.md` correctly
   postdates it. Trust `doc/` over `.design/` claims.

Notable absences: no `draft-syn` synthesis for the composition wave; no
representation-migration policy; no native config/apply flow decision; no
reconciliation of `install` render-time vs operator-time semantics beyond
use-cases1's phase-dimension finding; no live flow-execution run anywhere.

## Implementation vs intent (verified snapshot)

| Intent | State | Evidence |
|---|---|---|
| Omnibus multicall runtime + alias dispatch | Done | `build/runtime/compfuzor-runtime.mjs`; [log.md L113-131](/doc/config/log.md) |
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
| Effect foundation | Chosen, not implemented | [effect-draft0.gpt6a.md §1](/design/compfuzor-runtime/effect-draft0.gpt6a.md) |
| Archive-alias → workspace adoption | Implemented + verified | `wqtvrvqpqwto` etc., Sep 29 |

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

Plausible coherent slices, each grounded in a doc's own recommendation:

- **Repair-first:** finish assess0 remediation #1 (declare the four stale
  paths `BINS_ABSENT` in `zim.opt.pb`, re-render, verify aliases), then
  rehearse the zim2 cutover (assess0 #2/#3). Restores production and retires
  the recurring failure class before any design work rides on it.
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

> Resume the compfuzor runtime/composition effort. Read
> /doc/config/README.md, /design/config-anneal/execution-model0.gpt6.md (esp.
> the L591-605 matrix), /design/compfuzor-runtime/assess0.glm53fm.md,
> /design/runtime-config-lane/assessment0.gpt61sol.md, and the Sep 26
> composition-problem0 + both draft1s. Distinguish the four adoption meanings
> (runtime upgrade of existing installs; second adopters of shared contracts;
> archive custody — done; Effect — chosen not started). Decide first whether
> to repair zim-main's half-finished multicall migration (BINS_ABSENT +
> re-render) or to synthesize the composition/Effect direction first; do not
> add `config`/`apply` to flow allowlists until the domain-action-vs-flow and
> flows-schema-survival decisions are made.
