---
type: AgentHandoff
title: Registry implementation architectural lead handoff
description: Current user decisions, active agents, accepted upstream work, code checkpoints and remaining architecture/verification responsibilities for a fresh lead.
resource: /design/registry-discovery/handoff0.gpt6a.md
tags: [handoff, registry, implementation, ownership, rollover]
status: draft
generated: { by: model:gpt6a, at: 2026-10-07 }
verified: { by: unverified }
stale_after: 2026-10-14
---

# Resume here

The user asked us to build Compfuzor's shared registry/rendezvous system with **Sol
medium implementation agents**, and asked **G** to improve the reusable Figments
drop-in loader. G's work is complete and all six recorded Figments features are
accepted/closed. Compfuzor has an executable library/CLI/generator/native slice;
the combined-first-install and coherent policy slice has now been committed and
reported verified, ready for successor source review and regression migration.

The current parent is **GPT-6 Astra xhigh**, petname **glowing-orchid**, session
`ses_eeca88ca4ffeNJOs4u3yLQAIVJ`. Its context was measured at roughly **488k** during
handoff preparation. The user's rollover policy is **350–450k normally**, targeting
about 400k; high-value expertise may justify up to **550k**. This parent is using
that exception for architectural continuity while arranging rollover.

# User decisions that supersede older proposals

1. **Registry is a reusable library/helper for pipeline tools.** Each domain's
   providers/consumers rendezvous is an instance, not a central catalog daemon.
2. **Symmetric self-registration through symlinks.** Media-keys publishes a link to
   its exact producer manifest into an XDG providers directory; Niri/Umbriel link
   their own consumer descriptions into a separate directory; Zim offers use another
   domain directory. Payloads stay owned by their playbooks/deployments.
3. **Reusable tool code belongs under `runtime/<domain>/`.** Earlier proposed
   `files/discovery/` placement was explicitly corrected. Existing domain/native
   code still lives in `files/`; wholesale migration is not required.
4. **Disabled and masked are distinct.** Retained `.disabled` entries and
   `enabled:false` metadata express inert participation. `/dev/null` mask overlays
   remain a veto.
5. **`--force-enable`** is the human-selected invocation-only override for
   registration disables. It works for default collection and explicit subsets,
   preserves saved state, and does not bypass masks/audience/schema/native validation.
   Existing consumer-owned producer-group and per-binding/action disables are
   distinct lower-level policy and remain preserved.
6. Use **`@bomb.sh/router` and `@bomb.sh/tab`**, not Gunshi. Published Router 0.7.1
   differs from GitHub main; the implemented CLI uses the verified published API.
7. The user asked new Figments requirements to be recorded as **features in that
   project**. This was done with scoped acceptance and dependency links.

Canonical current direction: [rendezvous](/design/registry-discovery/rendezvous0.gpt6a.md),
[ownership](/design/registry-discovery/ownership0.gpt6a.md),
[selection](/design/registry-discovery/selection0.gpt6a.md).

# Active agents and assignments

## Retired implementing Sol medium

Session: `ses_eeaabf886ffe9Olh3sg1Th1RxZ`.

Its latest completed checkpoint is
[`implementation2.gpt61s.md`](/design/registry-discovery/implementation2.gpt61s.md),
with [its code handoff](/design/registry-discovery/handoff0.gpt61s.md).
It returned at **404,514 current tokens** (final harness readout about412k), within
the rollover band. It has stopped; do not assign another build to that session.
The completed bounded slice addressed
[publication0](/design/registry-discovery/publication0.gpt6a.md):

- explicit prospective owned consumers for combined first install;
- reusable exact pre-state → planned reference publication expectations;
- coherent provider/consumer policy injection through public/typed/generated inputs;
- same-byte selection-policy capture;
- producer overlay/owned workload agreement;
- authored receiver audience filtering before lookup;
- combined-role and isolated SYSTEM native proofs.

Reported new commits: `92f2dcf6`, `99e516f3`, `106a9da2`. Reported verification:
55 focused tests, `pnpm check`, refreshed bundle, combined USER/SYSTEM native proof
with rollback, and the previous media-keys/Niri/Umbriel/Zim proof. The successor
must read the consequential code and handoff; this retiring parent has not reviewed
the new slice's full implementation and does not claim to have rerun its checks.

## Active rollover lead: Sol medium

Session: `ses_eea1fae6bffeVu5nRXam8lmMLb`.

Its read-only investigation is complete and committed as `392cdb66`:
[regression-map0.gpt61s.md](/design/registry-discovery/regression-map0.gpt61s.md).
It classifies old keybindings/action integration coverage into retained behavior,
obsolete wrapper/default assumptions, real gaps and isolation prerequisites. It
ran no tests/deployments and modified only that report. Reported context at return
was about **125.6k**. It has now been promoted and restarted as the **rollover lead
and implementation successor**, using the already user-requested Sol medium model.
Repeated server restarts interrupted the optional fresh-model choice, so continuation
uses that existing model direction rather than waiting on the same question again.

It is assigned to review implementation2's consequential code, then implement the
remaining regression/fixture/documentation migration from its report. It owns
architectural judgment for that continuation. The old parent becomes a light relay
and should not redo the successor's research.

It must not blindly run old SYSTEM/native integration tests: some have isolated
native outputs but still use live default registry locations. The mapping is now
complete; the public registry-policy pair must be bound before running those proofs.

## Completed G / Figments

Session: `ses_eeae3db73ffeDmpfLFL58ESmtJ`. Finished around287k context; no further
work is assigned. Repository: `~/src/figments`.

Accepted features under `fig-config-layout-toolkit`:

- `fig-config-layout-toolkit-source-inventory`
- `fig-config-layout-toolkit-entry-resolution`
- `fig-config-layout-toolkit-literal-registry-keys`
- `fig-config-layout-toolkit-captured-loading`
- `fig-config-layout-toolkit-dropin-modes`
- `fig-config-layout-toolkit-xdg-search-roots`

All six were verified closed via `bd list --status closed --label drop-in-discovery`.
Feature spec: `~/src/figments/design/drop-in-discovery/features0.gpt6a.md`.
G's revisions and code references: `proposal0.glm53.md`, `revision0.glm53.md`,
`revision1.glm53.md`, `revision2.glm53.md` in the same directory.
Final code fix `b61747f6`; final parent completion records commit `ef12dfa8`.

# Figments contract ready for use

- `discoverDropIns`: metadata inventory, absolute captured paths, retained disabled
  suffixes, symlink topology, precise direct `/dev/null` controls and attributed
  root/entry errors.
- `resolveDropIns`: whole-entry identity views, effective-layer precedence,
  retained lower conflicts/root reports and mask recognition independent of ordinary
  payload symlink following.
- `captureDropIns`, `verifyCapturedSource`, `VerifiedFile`: detached membership,
  required/non-searching reads with read-time topology verification. Honest residual
  filesystem race limits, not immutable bytes or atomic multi-source snapshots.
- `Keyed`/`keyed`: literal dotted/numeric identity segments.
- `xdgConfigDir(s)`, `xdgDataDir(s)`: explicit environment snapshots and absolute
  HOME/XDG binding.
- `dropIns`: preserved global root-major layered loading versus explicit whole-entry
  selection; named controls, disabled inclusion, captured source mode; invalid
  effective source errors by default unless explicitly excluded/profile-inactive.

Last G verification: **49 files / 485 tests**, type/lint/format all passing. Last
one-line callback correction: **operator-policy28/28**, tsgo/lint/format clean.
Parent read source and used targeted probes; do not rerun everything merely to
confirm that report. See Compfuzor
[evidence](/design/registry-discovery/evidence0.gpt6a.md) and
[substrate review](/design/registry-discovery/figments-review0.gpt6a.md).

Beads had a closure-persistence/re-import anomaly. Earlier separate close commands
were reverted on a later re-import. Closing prerequisites and F5 **together in one
command** with `--dolt-auto-commit on`, then verifying the JSONL and closed list,
restored all six. No database destruction or force-closing gates was used. The
accepted records and spec were committed afterward. Do not run `bd prime`.

# Current Compfuzor implementation

Start with the actual guides/code:

- [`runtime/registry/README.md`](/runtime/registry/README.md)
- [`runtime/registry/model.ts`](/runtime/registry/model.ts),
  [policy](/runtime/registry/policy.ts), [read](/runtime/registry/read.ts),
  [register](/runtime/registry/register.ts), [guards](/runtime/registry/guard.ts)
- [`runtime/discovery/figments.ts`](/runtime/discovery/figments.ts): all upstream
  integration in one adapter; dependency is relative `figmen-ts: link:../figments`
  using existing source subpaths, without absolute checkout paths in production.
- [`runtime/keybindings/invocation.ts`](/runtime/keybindings/invocation.ts),
  [domain descriptions](/runtime/keybindings/registry.ts),
  [`files/config/keybindings/runtime.ts`](/files/config/keybindings/runtime.ts)
- [typed action operations](/files/actions/operations.ts) and
  [session transport](/files/actions/session.ts)
- [`library/filter_plugins/keybindings_compile.py`](/library/filter_plugins/keybindings_compile.py),
  [registration generator](/library/filter_plugins/registry_compile.py),
  [keybinding generation task](/tasks/compfuzor/gen_keybindings.tasks)
- [generated native proof](/tests/integration/registry_keybindings_generated.test.py).

Checkpoint commits (git hashes reported by Sol):

| Stage | Commits |
|---|---|
| Library/CLI/source dependency | `19b837a6`, `6c110fbd`, `960743a6` |
| Policy/selector/completion refinement | `f312f304` |
| Advertised native batches / force / guards | `115955a6` |
| Generated registration / owned descriptions / bundled artifact | `b8c26e25` |
| Shared-root, check-publication and admission corrections | `ffd01dd2` |
| Executable checkpoint / successor notes | `7c6acd74` |
| Prospective consumers, exact transitions and public registry policies | `92f2dcf6`, `99e516f3`, `106a9da2` |

The committed `runtime/compfuzor-runtime.mjs` bundles the real Figments/confbox and
Router/tab closure (about1.16MB), so deployed use does not require sibling source
checkouts or receiver-side node_modules. New source development remains `.ts`.

Implementation1 reported **8 files /46 focused tests**, `pnpm check`, build,
compiler scripts, relevant playbook syntax checks, and generated media-keys +
Niri/Umbriel + second named Niri + Zim offer endpoints. Native validation/rollback
was real, beneath isolated HOME/XDG directories. The broad native Vitest attempt
exceeded120s; old per-target integration assumptions still require migration.
Implementation2 subsequently reports **55 focused tests**, checks/build and the
combined USER/SYSTEM proof. Use its handoff for exact commands and current evidence.

# Current architectural review findings / authorization

The full active instruction is summarized in
[publication0](/design/registry-discovery/publication0.gpt6a.md). In particular:

1. Combined producer+host admission cannot require an already-published receiver.
   Prospective consumer references must be explicit and guarded; no publication
   inside admission, no late widening of receiver membership.
2. Post-publication provider observation must satisfy the admitted exact transition.
   The prior implementation could accept a newly arriving mask as its new guard.
3. Selection policy must parse its guarded captured bytes, not read then capture a
   different revision.
4. Effective producer redirection must not be silently ignored or swap the explicit
   owner's workload. The authorized conservative contract requires operative offer
   agreement (participation controls may differ) or an explained pre-effects error.
5. Mixed-audience authored target lists must be filtered before current-audience lookup.
6. A public coherent policy pair is needed to avoid custom SYSTEM tests reading or
   publishing into live defaults. Do not invent a hidden test-only override.

Parent previously approved policy refinements: generic contained collection paths;
separate system namespace from shared user XDG offers; root-major config/mask
ordering; passive publication beneath higher masks; existing PathSelector forms;
undashed tab option names and normal completion protocol.

# Remaining destination and scope discipline

The fresh regression map should guide the next executable slice. Known remaining
directions to distinguish rather than claim completed:

- review/verification of the now-committed combined-role and system-policy integration;
- migration of retained old generated/native behavior tests and maintained guides;
- consumer-driven provider collection (current host assembly primarily reassembles
  accepted membership, not every newly registered offer);
- Zim offers are registered/inspectable, while existing native host import/discovery
  still uses its prior bridge;
- registry administration helpers beyond registration/status, where needed;
- registered native adapter extension (current native formats remain Niri/Umbriel);
- original changed→canonical→deployed runtime resolution, SHA-512 burns and lean
  delivery: **separate follow-on, not implemented by this registry slice**.

Do not silently stretch every discussed future into the current cutover. Ask a
focused user question when a future direction materially changes the seam, while
continuing independent agreed implementation.

# Working practice / preservation

- Read current AGENTS instructions. Background agents only; parent retains
  architecture and reviews code/evidence. Trust reported checks unless a new
  concern warrants additional verification.
- Use `jj commit -m ... <explicit owned paths>` at coherent checkpoints. No push,
  edit or squash. Do not routinely rerun jj commands just to verify commits.
- Existing unrelated work was present throughout: `.beads/issues.jsonl`, formatting
  in `files/config/registration.ts` and its test, deleted legacy scripts, `rc=02`,
  and some parent documentation changes. Investigate/preserve current state; do not
  restore snapshots or include unrelated changes in a new commit.
- The user's media-keys values evolved during the conversation. Use current
  `media-keys.etc.pb`, never restore older attached examples or defaults.
- Source experiments belong in domain-grouped `.test-agent/` with README; do not
  write live HOME/XDG or invoke privileged/native SYSTEM fixtures without explicit
  isolated policies. No live install has been authorized.
- Existing docs show proposals as well as implementations. Latest user decisions
  and actual reviewed source govern. Preserve predecessors and write new inquiry
  files with the actual model suffix.
