---
type: Research
title: Runtime/tool sourcing precedents — standard install or live checkout first, with bypass
description: Inventory of existing "little baby steps" toward resolving Compfuzor tools/runtime from a canonical host checkout or shared install instead of per-deployment bundling, with exact precedence, fallbacks, tests, and the gaps between them.
resource: /design/runtime-sourcing/precedents0.glm53.md
tags: [compfuzor, runtime, sourcing, archive, bootstrap, catalog, bypass]
status: draft
generated: { by: 'model:zai/glm-5.3', at: '2026-10-06' }
verified: { by: unverified }
stale_after: 2027-01-06
sources:
  - id: runner-tasks
    resource: /tasks/compfuzor/repo_jj_archive.tasks
    title: Implemented dual-path runner resolution
  - id: bootstrap-ticket
    resource: beads:compfuzor-runtime-bootstrap
    title: Open ticket for shared-runtime bootstrap
  - id: operator-direction
    resource: /design/compfuzor-runtime/composition-problem0.gpt6a.md
    title: Operator direction on early shared runtime
---

# Runtime sourcing precedents

## What is up

The operator wants deployments to stop expanding: rather than every rendered
deployment bundling a whole Compfuzor runtime (and every tool/catalog around
it), the system should "look for the standard compfuzor install first and
foremost by default (with a bypass) to load live, versus needing the on disk
copy" — with intent to source from the on-disk checkout at
`~/archive/rektide/compfuzor`, and to be able to turn off shipping the whole
runtime plus tools like the keybindings processor and the run-time catalog.

Terminology is ambiguous and must be kept distinct; three different things are
called "live"/"on disk"/"install" in the corpus:

| Meaning | Where it exists today | Status |
|---|---|---|
| **Live source checkout** — a jj/git worktree of compfuzor itself (`~/archive/rektide/compfuzor`, or any checkout rendering a playbook) | `COMPFUZOR_ARCHIVE` resolution, launcher source-vs-bundle | Implemented for one runner |
| **Shared installed runtime** — one host-wide runtime binary/alias used by many deployments | `cfr`/`cf-r` idea, `compfuzor-runtime-bootstrap` ticket, `composition-draft1` design | Designed/tracked only |
| **Per-deployment bundled copy** — each deployment's `bin/compfuzor-runtime.mjs` + aliases + catalog | `runtime_bundles.py`, `gen_runtime_catalog.tasks` | Implemented; the current default |

This document inventories the existing seams that already point toward the
first two meanings, with exact precedence and evidence, and identifies what
does not exist yet. It is read-only research; the parent session retains
architecture and user clarification. The keybinding target catalog/selection
trace is the parent's separate task — only the delivery/env seams around it
are covered here.

## Implemented seams

### 1. The headline baby step: archive runner dual-path resolution

[`tasks/compfuzor/repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks)
already implements exactly the requested shape — canonical host checkout
preferred, executing copy as always-available fallback, explicit override as
the bypass — for one tool (the jj archive runner):

1. **`COMPFUZOR_REPO_JJ_RUNNER`** (Ansible var) overrides everything —
   "the escape hatch for a stale or broken host checkout"
   ([L28-34](/tasks/compfuzor/repo_jj_archive.tasks#L28-L34)).
2. **Host canonical checkout** `COMPFUZOR_ARCHIVE/script/repo-jj-archive.ts`
   when its launcher is executable (stat-gated, [L22-26](/tasks/compfuzor/repo_jj_archive.tasks#L22-L26)),
   so refreshes "run the freshest toolkit rather than whatever checkout
   renders this playbook".
3. **Executing playbook's launcher** `playbook_dir ~ '/script/repo-jj-archive.ts'`
   as the fallback that always works.

`COMPFUZOR_ARCHIVE` defaults to `{{ARCHIVE_DIR}}/rektide/compfuzor` =
`~/archive/rektide/compfuzor`
([vars/common.yaml L21-29](/vars/common.yaml#L21-L29)), with the task's own
inline fallback `lookup('env', 'HOME') ~ '/archive/rektide/compfuzor'`. The
comment block is explicit that this is the "house archive convention; not yet
guaranteed to exist" — a preference, not a requirement.

Supporting knobs, same file:

- **`COMPFUZOR_SELF_FRESHEN=true`** (opt-in, default false): fetches the host
  checkout's origin before resolution — fetch only, never a worktree reset;
  a missing checkout is a clean no-op ([L13-20](/tasks/compfuzor/repo_jj_archive.tasks#L13-L20)).
- **An announce task** names which source won (`override` / `host compfuzor
  checkout` / `playbook checkout`, [L36-43](/tasks/compfuzor/repo_jj_archive.tasks#L36-L43)) —
  resolution is observable, not silent.
- `JJ_BYPASS` gates the whole lane.

**Audience distinction**: all three knobs are controller-side Ansible vars
(set via playbook/`-e`), consumed at render time. This is *not* a runtime env
knob.

**Proof**: [`test_runner_prefers_host_checkout_with_playbook_fallback`](/tests/integration/repo_jj_archive.test.py#L1239)
asserts all three precedence outcomes plus that opt-in freshen advances
`origin/main` without resetting the host worktree
([L1301-1319](/tests/integration/repo_jj_archive.test.py#L1301-L1319));
[`test_fine_grained_commands_and_opt_in_checkout_detection`](/tests/integration/repo_jj_archive.test.py#L1187)
covers `self --freshen` including the "No compfuzor archive" no-op.
[`tests/integration/build_mise.test.py` L199](/tests/integration/build_mise.test.py#L199)
pins `COMPFUZOR_REPO_JJ_RUNNER` to the repo's own script path — the override
also serves to make tests deterministic against a host checkout. The contract
is documented in [`archive/README.md` L433-442](/archive/README.md#L433-L442).

### 2. Launcher source-then-bundle (live TS vs committed bundle)

[`script/repo-jj-archive.ts`](/script/repo-jj-archive.ts) is a thin shim whose
resolution ([L23-38](/script/repo-jj-archive.ts#L23-L38)) prefers
`archive/src/repo-jj-archive.ts` run directly via Node type stripping — "no
bundler transport between checkout and execution" — when source *and* the
`node_modules` Effect deps are present, else the committed single-file bundle
`archive/repo-jj-archive.ts` for "trees without source or locally installed CLI
dependencies". Proven by
[`test_launcher_uses_standalone_bundle_without_source_or_node_modules`](/tests/integration/repo_jj_archive.test.py#L1207),
including that a present-but-unusable source must not mask the bundle.

Known limit (design, not fixed): on Node 20 the TS launcher itself dies before
its resolution logic runs; the documented zero-code story is overriding
`COMPFUZOR_REPO_JJ_RUNNER` to the bundle
([`design/archive-toolkit/runtime-checks0.glm53.md` F2, L77-101](/design/archive-toolkit/runtime-checks0.glm53.md#L77-L101)).

### 3. Zim host discovery — the run-time analogue, registry-as-link

Generated `install-zimfw.sh` host discovery
([`tasks/compfuzor/gen_zim.tasks` L166-189](/tasks/compfuzor/gen_zim.tasks#L166-L189)):

1. `ZIM_HOST_DIR` env override wins.
2. Canonical registry link `~/.config/zsh/zimfw.conf` → resolve → derive the
   owning deployment dir → accept it if `bin/install-zim.sh` is executable.
   "the link IS the registry" — every zim host install creates it via
   [`files/zim-registry.sh`](/files/zim-registry.sh) (itself driven through
   the deployment's own `bin/links.mjs`, with a `ZIM_CONFIG_LINK` override).
3. Fallback `/opt/zim-main` (the `OPTS_DIR` default location).
4. Host absent → **graceful skip** (`_cf_report_skip`) with an actionable
   message ("set ZIM_HOST_DIR"), not a failure.

This is the only implemented place where one deployment *executes another
deployment's* installed tooling at run time, discovered through a
conventional shared location with env override and default fallback. Note the
distinction from seam 1: this is receiver-side (generated bin, run time, env
var), not controller-side.

### 4. Runtime + catalog delivery: per-deployment default, presence-gated extras, explicit-target overrides

Current implemented default is the **per-deployment bundled copy**:
[`library/filter_plugins/runtime_bundles.py`](/library/filter_plugins/runtime_bundles.py)
emits one raw-copy claim for the checked-in
`runtime/compfuzor-runtime.mjs` (built by `pnpm build`, committed because "the
controller needs it while rendering arbitrary playbooks") plus symlink
aliases; the name-keyed BINS merge dedupes claims when several domains
participate ([`doc/config/consumer-toolkit.md` L36-113](/doc/config/consumer-toolkit.md#L36-L113)).
`links_runtime_bins(False)` (the default) returns *no* delivery code — "delivery
is bundled by its consumer" ([`library/README.md` L195](/library/README.md#L195)).

Two implemented behaviors already lean away from "ship everything":

- **Presence gating**: `compfuzor-catalog.sh` ships only when the deployment
  already carries the omnibus runtime (`_runtime_present` scan over BINS) or
  when `RUNTIME_FLOW_EXECUTION: true` opts in
  ([`tasks/compfuzor/gen_runtime_catalog.tasks` L20-36](/tasks/compfuzor/gen_runtime_catalog.tasks#L20-L36));
  catalog *data* (`etc/compfuzor-runtime/catalog.json`) lands everywhere but
  "ordinary deployments are not forced to add a Node runtime merely for
  catalog emission".
- **Explicit-target overrides**: the deployed multicall runtime infers its
  deployment from its own physical location
  ([`files/runtime/compfuzor-runtime.ts` L153-157](/files/runtime/compfuzor-runtime.ts#L153-L157):
  `dirname(..)/..` for the deployed `.mjs`), and the catalog/flow CLIs offer
  `--deployment DIR` / `--catalog PATH` to operate on a foreign deployment
  ([`files/catalog/runtime.ts` L127-147](/files/catalog/runtime.ts#L127-L147),
  [`files/flow/runtime.ts` L47-66](/files/flow/runtime.ts#L47-L66)) — the
  seam a shared runtime would need, already present as an escape hatch.

Also implemented: `action_audiences.py` generates `.mjs` entry files that
`import { actionEntry } from "./compfuzor-runtime.mjs"`
([L92](/library/filter_plugins/action_audiences.py#L92)) and appends the
runtime claim only if not already occupied
([L250-251](/library/filter_plugins/action_audiences.py#L250-L251)) — a
deployment-relative import that presumes the co-located copy.

### 5. The bypass env-var law

[`files/_helpers/guard` L26-45](/files/_helpers/guard#L26-L45) defines the
convention every generated bin inherits: `_cf_guard_bypass` skips when
`COMPFUZOR_<CONCERN>_BYPASS` is non-empty, `_cf_guard_bypass_unit` for
`COMPFUZOR_<CONCERN>_<UNIT>_BYPASS`. Live consumers today include
`COMPFUZOR_CONFIG_BYPASS`, `COMPFUZOR_ZIM_BYPASS`,
`COMPFUZOR_KEYBINDINGS_BYPASS`, `COMPFUZOR_APT_UPDATE_BYPASS`,
`COMPFUZOR_SYSTEMD_LINK_BYPASS`, `COMPFUZOR_MISE_BYPASS`,
`COMPFUZOR_OWN_BYPASS`, `COMPFUZOR_ENV_BYPASS`, and unit-shaped ones like
`COMPFUZOR_DIRECT_TOOLS_APPLY_NETWORK_BYPASS`
([`tests/integration/bin_helpers.test.py` L224-267](/tests/integration/bin_helpers.test.py#L224-L267)).
There is **no** `COMPFUZOR_RUNTIME_BYPASS` / runtime-source knob — the naming
law exists, the runtime-sourcing concern does not.

Related expectation-altering runtime knobs (same "baked default, env
overrides for this run" shape, called out in
[`vars/common.yaml` L940-944](/vars/common.yaml#L940-L944) for `APT_INSTALL`):
`COMPFUZOR_MISE_LINK_FORCE` and `TOOL_VERSIONS_LINK_BYPASS` in
[`tasks/compfuzor/gen_tool_versions.tasks` L48-91](/tasks/compfuzor/gen_tool_versions.tasks#L48-L91),
`COMPFUZOR_LINK_OVERWRITE`, `COMPFUZOR_LINKS_SUDO`.

### 6. Provenance and checkouts-as-sources

- [`library/lookup_plugins/playbook_identity.py`](/library/lookup_plugins/playbook_identity.py#L44-L70)
  resolves *which checkout rendered this* from `COMPFUZOR_PLAYBOOK_PATH` →
  Ansible CLI args → legacy `/proc/self/cmdline`, retaining ambiguity rather
  than guessing — a provenance pattern reusable for "which runtime instance
  produced this deployment".
- The whole archive lane is premised on deployments sourcing code from a
  shared live checkout: `ARCHIVE_DOWNLOAD`/`ARCHIVE_SRC`
  ([`vars/common.yaml` L21, L56-57](/vars/common.yaml#L21)) route `REPO`
  through the runner into a **dedicated jj workspace** backed by
  `~/archive/<org>/<repo>`, precisely so "state of the archive main working
  copy should not matter"
  ([`design/archive-deployment-premise/draft0.glm53.md` L40-50](/design/archive-deployment-premise/draft0.glm53.md#L40-L50)).
  The deployment then *builds* from that workspace — i.e. "run from the live
  checkout" is already the normal shape for target software; what is bundled
  is only Compfuzor's own tooling.
- Vendored-controller precedent: `runtime/zimfw.zsh` is a pinned vendored copy
  while deployments GET_URLS-fetch a fresh copy per deployment
  ([`zim.opt.pb` L69-70](/zim.opt.pb#L69-L70)); "gen_zim/GET_URLS preferring
  the vendored copy over download" is an explicit open item
  ([`design/compfuzor-runtime/zim-pieces0.glm53m.md` L75-80, L99](/design/compfuzor-runtime/zim-pieces0.glm53m.md#L75-L80)) —
  the same live-vs-bundled tension one level down.

## Designed-only seams (not implemented)

- **`compfuzor-runtime-bootstrap` (beads, open, P2)**: "Bootstrap a shared
  Compfuzor runtime from its own checkout." Records the operator
  clarification that `cf-r` was an idea, not an existing executable; initial
  implementation should be "an ordinary Compfuzor checkout with its bins
  installed system-wide, exposing the checked-in runtime/compfuzor-runtime.mjs";
  ideally the local runtime can install itself globally without a pre-existing
  global runtime; "copy versus checkout-backed link remain design choices";
  and "installing globally must distinguish runtime installation location from
  the target project/deployment context; current real-module-path inference
  requires review" (`.beads/issues.jsonl`, see also
  [`composition-problem0.gpt6a.md` L73-82](/design/compfuzor-runtime/composition-problem0.gpt6a.md#L73-L82)).
- **Host-installed `cfr` design** ([`composition-draft1.glm53.md`](/design/compfuzor-runtime/composition-draft1.glm53.md)):
  "The host ships the executor; deployments ship data" — `cfr.opt.pb` would
  install `/usr/local/lib/compfuzor/compfuzor-runtime.mjs` +
  `/usr/local/bin/cfr`; deployments carry a registry the runtime reads;
  version-floor negotiation; **when `cfr` is missing, render still succeeds**
  and compositors keep full `run_all` bodies as fallback; open question 7
  explicitly contrasts thin `exec cfr` shims (assumes host runtime) vs
  full-body shims ([L221-242, L481-487](/design/compfuzor-runtime/composition-draft1.glm53.md#L221-L242)).
  Verified at draft time that no `cfr`/`cf-r`/`compfuzor` executable exists on
  PATH ([L529](/design/compfuzor-runtime/composition-draft1.glm53.md#L529)).
- **Bootstrap probes**: experiment 4 demonstrated, in scratch only, a
  checkout-local runtime entry installing a (fake) global symlink without a
  pre-existing global command, plus the irreducible controller glue of
  reporting "missing; run checkout-local runtime.install first"
  ([`experiment4.sxh.md` L178-212](/design/compfuzor-runtime/experiment4.sxh.md#L178-L212));
  experiment 1 recorded the `cf-r` disambiguation
  ([L40-42](/design/compfuzor-runtime/experiment1.sxh.md#L40-L42)).
- **Default directory discovery** (latest direction synthesis,
  [`effect-draft2.gpt6a.md` §3](/design/compfuzor-runtime/effect-draft2.gpt6a.md)):
  the common runner would discover executable `.ts` contributions recursively
  by default — discovery roots and precedence are explicitly still-open
  design ([`world-map0.gpt61sol.md` L98-103](/design/compfuzor-runtime/world-map0.gpt61sol.md#L98-L103)).

## Hidden local-asset assumptions (what a shared-source seam must confront)

- **Controller checkout must contain a built runtime**:
  `runtime_bundles._REPOSITORY = Path(__file__).resolve().parents[2]`
  ([L12](/library/filter_plugins/runtime_bundles.py#L12)); rendering any
  CONFIG/LINKS/Zim/keybindings/actions deployment fails with "run `pnpm
  install` and `pnpm build`" if `runtime/compfuzor-runtime.mjs` is absent —
  there is no "use the host canonical checkout's artifact" fallback analogous
  to seam 1, and no way to say "don't ship it, resolve it at run time".
- **Deployment-relative imports**: generated action entries import
  `./compfuzor-runtime.mjs` from their own directory; bin `run_all`
  compositors exec siblings by deployment-relative path. A shared runtime
  changes these from copies to indirections.
- **Runtime location == deployment root**: `deploymentDirectory()` infers the
  deployment from the runtime module's real path; the catalog/flow
  `--deployment` overrides exist but there is "no uniform explicit-target
  contract" ([`world-map0` L82-91](/design/compfuzor-runtime/world-map0.gpt61sol.md#L82-L91)),
  which also caused a real duplicate-descriptor resolution failure in
  `/opt/zim2-main`.
- **Symlink-through-checkout execution**: default installs symlink bins
  through `DIR` (mode 0770) and the repo link "often ~/archive", which
  daemons under `ProtectHome=yes` cannot traverse — the documented reason
  `RUST_COPY=true` exists ([`vars/common.yaml` L472-481](/vars/common.yaml#L472-L481)).
  A live-checkout-backed runtime inherits this traversal/permission exposure.
- **Delivery-representation coupling**: flipping per-deployment artifacts
  between real files and symlinks previously broke renders ("refusing to
  convert from file to symlink") because copy and link claims travel different
  tasks ([`assess0.glm53fm.md` §5](/design/compfuzor-runtime/assess0.glm53fm.md#L124-L160));
  compfuzor also deliberately never prunes stale deployment files, so a
  sourcing cutover leaves old copies behind.
- **Node version floors**: direct-TS execution needs type-stripping Node;
  the launcher-is-TS gap on Node 20 is only mitigated by the
  `COMPFUZOR_REPO_JJ_RUNNER` override
  ([`runtime-checks0` F2](/design/archive-toolkit/runtime-checks0.glm53.md#L77-L101)).
- **Run-time tool assumptions**: `build-mise.sh` assumes `mise` on PATH;
  keybinding consumer defaults point at a *shared* location
  `${XDG_DATA_HOME}/compfuzor/etc/<niri|umbriel>/etc/keybinding-*.json` with
  env selection (`COMPFUZOR_NIRI_PROFILE`/`COMPFUZOR_UMBRIEL_PROFILE`,
  [`vars/common.yaml` L204-220](/vars/common.yaml#L204-L220)) — a
  consumer-side shared-source seam that already exists; the producer side
  still ships per deployment (parent session traces this catalog).

## What does not exist (the actual gap)

No knob today selects the *source* of `compfuzor-runtime.mjs` or its sibling
tools: every deployment that declares a runtime-consuming domain gets a copy,
unconditionally, from the rendering checkout's built artifact. There is no
`COMPFUZOR_ARCHIVE`-style preference for a canonical checkout's (fresher)
artifact, no `*_BYPASS` to omit the runtime from a deployment, and no
run-time resolution of the runtime or catalog from a shared install. The
catalog *reader* is already presence-gated, `RUNTIME_FLOW_EXECUTION` is an
opt-in *adder*, and `--deployment` overrides cover foreign-deployment
operation — but nothing composes these into "prefer the standard install,
fall back to bundled, allow turning bundled off".

## Reusable seam candidates

1. **Replicate the repo_jj_archive triple** (explicit override → canonical
   host checkout when its artifact is present → executing checkout), with its
   stat-gate, announce task, and opt-in freshen, for the runtime artifact
   claim in `runtime_bundles.py` / `gen_runtime_catalog.tasks`. The
   `_runtime_present` scan is the natural inversion point: "shared runtime
   resolves" instead of "deployment already carries one".
2. **Zim host discovery as the run-time pattern** (env override →
   conventional registry link → default path → graceful skip with a "set
   X" hint), including the registry-as-symlink trick, for a future
   `cfr`-style shared entry operating on foreign deployments — combined with
   the already-implemented `--deployment` explicit target.
3. **Launcher source-then-bundle** for any shipped tool: live checkout TS
   when source+deps exist, committed bundle otherwise; keep the "present but
   unusable source must not mask the bundle" test invariant.
4. **The `COMPFUZOR_<CONCERN>_BYPASS` naming law** for whatever concern ends
   up meaning "don't ship / don't use the shared runtime" — plus the
   pinned-override-in-tests precedent (`build_mise.test.py` L199) so tests
   stay deterministic while hosts vary.
5. **`playbook_identity`'s retain-ambiguity provenance** for recording which
   runtime source rendered a deployment, feeding the existing catalog
   attribution (`execution.authority`-style) rather than a new registry.

None of these require the broader contribution-registry redesign; the
bootstrap ticket itself states it is "a bounded bootstrap feature, separable
from the broader contribution-registry and composition redesign."

## Unresolved ambiguities for the parent

- Whether the user's "standard compfuzor install" means the live checkout
  (seam 1 generalization) or the not-yet-existing shared installed runtime
  (bootstrap ticket) — the two have different fallback floors (playbook copy
  vs per-deployment copy) and different audiences (controller vs receiver).
- Whether "turn off sending … the specific catalog at time of run" means a
  render-time shipping switch (extend `_runtime_present`-style gating) or a
  run-time authority switch (catalog `--catalog` pointing at a shared/live
  source).
- Copy vs checkout-backed link for any shared artifact remains an open
  design choice in the bootstrap ticket; the `RUST_COPY` daemon-traversal
  precedent and the file→symlink migration failure both bear on it.

## Cross-references

- [`tasks/compfuzor/repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks) —
  the implemented canonical-checkout-first resolution this inquiry centers on.
- [`design/compfuzor-runtime/composition-problem0.gpt6a.md`](/design/compfuzor-runtime/composition-problem0.gpt6a.md) —
  operator direction preserving "early shared runtime is on the table" and
  the runtime-location ≠ deployment rule.
- [`design/compfuzor-runtime/composition-draft1.glm53.md`](/design/compfuzor-runtime/composition-draft1.glm53.md) —
  the most complete designed host-runtime story (install, floor,
  missing-runtime fallback, shim question); independent wave output, not
  accepted design.
- [`design/compfuzor-runtime/experiment4.sxh.md`](/design/compfuzor-runtime/experiment4.sxh.md)
  and [`experiment1.sxh.md`](/design/compfuzor-runtime/experiment1.sxh.md) —
  scratch-evidence bounds on self-install and the cf-r disambiguation.
- [`design/compfuzor-runtime/world-map0.gpt61sol.md`](/design/compfuzor-runtime/world-map0.gpt61sol.md) —
  present-world map naming the missing "uniform explicit-target contract"
  this inquiry's seam candidates would fill.
- [`design/compfuzor-runtime/zim-pieces0.glm53m.md`](/design/compfuzor-runtime/zim-pieces0.glm53m.md) —
  `runtime/` as local-first artifact home and the vendored-vs-fetched zimfw
  open item, a sibling of the sourcing question.
- [`design/compfuzor-runtime/assess0.glm53fm.md`](/design/compfuzor-runtime/assess0.glm53fm.md) —
  delivery-representation migration failure; caution for any copy↔link
  cutover.
- [`design/archive-toolkit/runtime-checks0.glm53.md`](/design/archive-toolkit/runtime-checks0.glm53.md) —
  Node-version reality of the source-vs-bundle launcher.
- [`design/archive-deployment-premise/draft0.glm53.md`](/design/archive-deployment-premise/draft0.glm53.md) —
  the archive/workspace premise: deployments already live against a shared
  checkout for target software.
- [`doc/config/consumer-toolkit.md`](/doc/config/consumer-toolkit.md) —
  controller-vs-deployed runtime split, catalog posture, and
  `RUNTIME_FLOW_EXECUTION` as the standing opt-in-delivery precedent.
- [`design/repo-jj-archive/scaffold0.glm53max.md`](/design/repo-jj-archive/scaffold0.glm53max.md) —
  as-built record of the dual-path contract and its deliberate non-goals.
- beads `compfuzor-runtime-bootstrap` (open) — the tracked home for the
  shared-runtime work this inquiry feeds; also references
  `files/runtime/compfuzor-runtime.ts` and `library/filter_plugins/runtime_bundles.py`.
- [`design/keybindings/current-config0.gpt6a.md`](/design/keybindings/current-config0.gpt6a.md) —
  keybinding domain doc whose `cfr-direction` source ties this corpus to the
  parent's keybinding trace; not analyzed here.
