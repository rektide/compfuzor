---
type: Design assessment
title: compfuzor-runtime effort — grounded state of the world
description: Read-only zoomed-out assessment of the compfuzor-runtime / zim2 / mise2 effort as of 2026-09-18, including root cause of the zim playbook file-to-symlink refusal.
status: draft
generated: { by: agent:glm53fm (GLM 5.3 Flash Max via OpenCode), at: 2026-09-18 }
verified: { by: none, at: null }
stale_after: 2026-10-02
sources:
  - id: repo-state
    resource: /home/rektide/src/compfuzor (jj @ yxlsmoqrksxp, 20h ago)
    title: compfuzor working copy + /opt on-disk state
    author: rektide
    last_modified: 2026-09-18
---

# compfuzor-runtime: where the effort stands (assess0)

Stage setting: this wave was spawned to ground a decision. The compfuzor-runtime
effort ran hot ~4-5 days ago (Sep 13-14) and has been dormant since — the last
runtime commit is `lktmymmtpvll` "review: close catalog flow execution blockers"
(4 days ago); the last 20+ commits are SteamOS/cifs/polytoken work. The zim
playbook failed on a fresh run today (Sep 18 13:34) with ansible "refusing to
convert from file to symlink" at `/opt/zim-main/bin/links/links.mjs` and
`/opt/zim-main/bin/zim/install.mjs`. This doc maps the effort, reconciles
on-disk vs declared state, and roots that failure in the delivery-model
migration.

## 1. Philosophy — what the effort is trying to be

Compfuzor's contract ([`/README.md`](/README.md)) is compile-and-apply: Ansible
playbooks declare intent, filter plugins compile it on the controller, and the
apply phase materializes files/bins/links. The compfuzor-runtime effort extends
that contract past deploy-time into *run-time*, with three moves:

1. **One runtime, not many.** Every per-subsystem JavaScript tool (links
   manager, zim installer, config command, config-remote, catalog, flow runner)
   collapses into a single checked-in Vite+ bundle,
   `build/runtime/compfuzor-runtime.mjs` (~139 KB on disk), built from
   domain-grouped sources under [`files/runtime/compfuzor-runtime.ts`](/files/runtime/compfuzor-runtime.ts)
   and `files/{config,config-remote,catalog,flow,links,zim}/`. Commit
   `swvsszxqnznl` (git `b68093eb`, Sep 13) "runtime: unify configuration tools
   in one multicall artifact" is the hinge.
2. **Lexical alias dispatch.** Deployments never invoke `compfuzor-runtime.mjs`
   by name; they invoke stable aliases (`bin/links.mjs`, `bin/zim/install.mjs`,
   `bin/config/command.mjs`, `bin/compfuzor-catalog.sh`, `bin/compfuzor-flow.sh`)
   that are *symlinks* to the one artifact. The runtime identifies its domain by
   walking its own invocation symlink chain and classifying each name
   ([`files/runtime/compfuzor-runtime.ts:29-39`](/files/runtime/compfuzor-runtime.ts#L29-L39)
   `classifyCandidate`,
   [`:41-60`](/files/runtime/compfuzor-runtime.ts#L41-L60) `invocationChain`).
   One copy of code per deployment dir; aliases are cheap, and stale-bundle
   drift becomes structurally impossible going forward — exactly one code
   artifact exists to be stale.
3. **A catalog as the machine-readable twin of a deployment.**
   `gen_runtime_catalog.tasks` compiles an attributed
   `etc/compfuzor-runtime/catalog.json` (contributors like
   `deployment:zim2-main`/`subsystem:aptlane`, actions with handler paths and
   protocols, indexed `flows` inventory) plus compiled workflow JSONs. The
   catalog is read-only by default; sequential *execution* of catalog flows is
   opt-in via `RUNTIME_FLOW_EXECUTION: true`, and hardened (realpath containment,
   process-group signals, closed handler selection) per
   [`doc/config/log.md`](/doc/config/log.md) 2026-09-14 entries.

Important scoping correction to how the effort is sometimes described: **zim2
and mise2 are not replacements for zimfw or mise.** The zim2 loader templates
still source `init.zsh` compiled by real zimfw
([`zim2.opt.pb:295-322`](/zim2.opt.pb#L295-L322)); mise2 still shells out to
real `mise` ([`mise2.opt.pb:89-116`](/mise2.opt.pb#L89-L116)). What zim2/mise2
replace is the *deployment shape*: catalog authority, one runtime artifact, and
isolated user state (`~/.cache/zim2`, `~/.config/zsh/zim2`, `~/.config/mise2`)
so experiments cannot touch the production shell.

## 2. Architecture map

Compile order lives in [`tasks/compfuzor.includes`](/tasks/compfuzor.includes):
`gen_config` (L72) → `gen_zim` (L74) → `gen_links` (L111) →
`gen_runtime_catalog` (L125) → fs apply → `bins.tasks` render →
`bins_link.tasks` (L203, delayed phase L232).

| Piece | Where | Role |
|---|---|---|
| Multicall entry | [`files/runtime/compfuzor-runtime.ts`](/files/runtime/compfuzor-runtime.ts) | Symlink-chain domain dispatch; direct invocation falls through to explicit `<domain> …` argv (L71-85) |
| Build | [`vite.config.ts:6`](/vite.config.ts#L6) | One entry `compfuzor-runtime` → `build/runtime/compfuzor-runtime.mjs`, checked in |
| Delivery claim (copy) | [`library/filter_plugins/runtime_bundles.py:16-36`](/library/filter_plugins/runtime_bundles.py#L16-L36) | `runtime_artifact_bin` — `raw: True` claim; fails fast pre-render if build artifact missing |
| Delivery claim (alias) | [`runtime_bundles.py:39-49`](/library/filter_plugins/runtime_bundles.py#L39-L49) | `runtime_alias_bin` — `link: compfuzor-runtime.mjs` claim |
| Links aliases | [`runtime_bundles.py:57-64`](/library/filter_plugins/runtime_bundles.py#L57-L64) | `links_runtime_bins(True)` → artifact + `links/links.mjs` + `links.mjs`; `links_runtime_dirs` adds `bin/links/` (L68-72) |
| Raw copy apply | [`tasks/compfuzor/bins.tasks:73-83`](/tasks/compfuzor/bins.tasks#L73-L83) | "Copy raw `BINS` into place" — `copy` module, overwrites real files fine |
| Symlink apply | [`tasks/compfuzor/bins_link.tasks:2-15`](/tasks/compfuzor/bins_link.tasks#L2-L15) | `file: state=link`, **no `force`** — refuses to replace an existing regular file |
| Zim host synthesis | [`tasks/compfuzor/gen_zim.tasks:191-220`](/tasks/compfuzor/gen_zim.tasks#L191-L220) | Merges `zim_context_compile(...).bins` + `links_runtime_bins` + donor/context scripts; dirs `bin/zim` + `bin/links` (L193-194) |
| Zim context compile | [`library/filter_plugins/zim_context_compile.py:114-123`](/library/filter_plugins/zim_context_compile.py#L114-L123) | `compfuzor_runtime_bins("zim/install.mjs")` + `install-zim.sh` + `status-zim.sh`; emits `etc/zim.spec.json` (L151) |
| Contributor bridge | [`gen_zim.tasks:127-189`](/tasks/compfuzor/gen_zim.tasks#L127-L189) | Auto `install-zimfw.sh` discovers host via `zimfw.conf` registry link (fallback `/opt/zim-main`, L184) and calls host's `install-zim-context.sh` |
| Config context compile | [`library/filter_plugins/config_context_compile.py:179-184`](/library/filter_plugins/config_context_compile.py#L179-L184) | collision guard + `compfuzor_runtime_bins("config/command.mjs")`; `config-*.sh` action aliases → `link: config/command.mjs` (L260-274); [`library/filter_plugins/config_compile.py:256`](/library/filter_plugins/config_compile.py#L256) adds `config-remote.mjs` alias |
| Catalog compile | [`tasks/compfuzor/gen_runtime_catalog.tasks`](/tasks/compfuzor/gen_runtime_catalog.tasks) | Always contributes `etc/compfuzor-runtime/` data (L17-18); `compfuzor-catalog.sh`/`compfuzor-flow.sh` bins only when a runtime is already in BINS or flow execution is on (L21-36) |
| Catalog filter | [`library/filter_plugins/runtime_catalog.py:317-333`](/library/filter_plugins/runtime_catalog.py#L317-L333) | catalog.json + `workflows/{compiled,site}/` etc_files |

## 3. Completeness / status table

| Capability | State | Evidence |
|---|---|---|
| Multicall artifact + build | **Done** | `build/runtime/compfuzor-runtime.mjs` checked in; `swvsszxqnznl` Sep 13; bundle size recorded in `doc/config/log.md` |
| Alias dispatch (links/zim/config/catalog/flow/config-remote) | **Done** | `classifyCandidate` covers all aliases; umyymprrvuoq "preserve multicall aliases after containment checks" |
| Fresh-deployment end-to-end (new dirs) | **Works** | `/opt/zim2-main`, `/opt/mise2-main` fully materialized today (Sep 18 13:23-13:29), every alias a correct symlink |
| Catalog compile + attribution | **Done** | `runtime_catalog.test.py`, `catalog.json` present in all four deployments; contributors/actions/flows populated |
| Flow execution (opt-in) | **Contained-dry-run validated only** | `doc/config/log.md` 2026-09-14: "passed safe install/status dry-runs" under `.test-agent/catalog-flow/`; blockers closed by `lktmymmtpvll`; no live-shell flow run yet |
| Upgrade-in-place of pre-multicall deployments | **Broken** | Today's `zim.opt.pb` run failed; see §5 |
| Production shell activation (old world) | **Active, untouched** | `~/.zshenv` `zim-main-zimenv` block (Sep 13 14:24) → `controller=/opt/zim-main/src/zimfw.zsh`; `~/.config/zsh/zimfw.conf → /etc/opt/zim-main/zimrc` (Sep 4) |
| New-world shell activation (zim2/mise2) | **Not started** | No `~/.cache/zim2*`, no `~/.config/zsh/zim2/`, nothing sources `~/.config/mise2/bashrc` |
| mise2 bash wiring | **Inert by construction** | `mise2.opt.pb` writes `~/.config/mise2/bashrc` (L35-36) which nothing sources; old `mise.opt.pb` wrote `~/.bashrc` directly (L34) |
| zim2/mise2 vs zim/mise dedup | **Deliberate duplication, already drifting** | `doc/config/log.md`: "isolated copies of the production playbooks"; module lists are full copies (`zim2.opt.pb:85-281` ≈ `zim.opt.pb:80-276`) |

## 4. On-disk vs declared reconciliation (read-only inspection)

| Deployment | Declared (playbook) | On disk | Verdict |
|---|---|---|---|
| `/opt/zim-main` | `zim.opt.pb` (production): runtime + `links/links.mjs`, `links.mjs`, `zim/install.mjs`, `config/command.mjs`, `config-remote.mjs` aliases + catalog | `compfuzor-runtime.mjs` real file (Sep 18 13:34, 139167B) ✓; `links.mjs`, `compfuzor-catalog.sh` symlinks ✓ (Sep 18 13:34); **`links/links.mjs` real file 31460B (Sep 13 08:06)**, **`zim/install.mjs` real file 67735B (Sep 13 08:06)**, also stale `config/command.mjs` 66443B + `config-remote.mjs` 6502B (Sep 13 08:06); catalog + compiled workflows present (Sep 18 13:34) | **Half-migrated**: last full old-world render Sep 13 08:06 (pre-unification); today's run converted what it could, refused the rest |
| `/opt/zim2-main` | `zim2.opt.pb`: same as zim + `RUNTIME_FLOW_EXECUTION`, isolated user state | All six aliases symlinked to `bin/compfuzor-runtime.mjs`; catalog + 5 compiled workflows; env points at `~/.cache/zim2` etc. | **Complete** new-world render (Sep 18 13:26-13:29); intentionally dormant until activated |
| `/opt/mise-main` | `mise.opt.pb`: plain bins only, no contexts | bins from Sep 13 07:29; **catalog.json + compiled workflows dated Sep 18 13:20** | **Catalog-without-reader half-state**: `gen_runtime_catalog.tasks:17` contributes catalog data unconditionally, but bins are gated (L21-36) and `mise.opt.pb` declares neither contexts nor flow execution |
| `/opt/mise2-main` | `mise2.opt.pb`: runtime + catalog + flow, isolated `~/.config/mise2` | `compfuzor-runtime.mjs` + `compfuzor-catalog.sh`/`compfuzor-flow.sh` symlinks + regular bins (Sep 18 13:23-13:24) | **Complete** for its declared scope; no config/zim/links domains because none are declared |

Sequence today inferred from mtimes: `mise.opt.pb` 13:20 → `mise2.opt.pb`
13:23 → `zim2.opt.pb` 13:26 → `zim.opt.pb` 13:32-13:34 (failed on conversions).

## 5. Root cause: the file→symlink refusal

The failure is an **unmigrated delivery representation**, not a bug in the new
code. Before `swvsszxqnznl` (git `b68093eb`), `links_runtime_bins(True)`
returned — verbatim from `jj file show -r 'b68093eb-'`:

```python
return [
    runtime_artifact_bin("links/links.mjs", "links/links.mjs"),   # RAW COPY → real file at bin/links/links.mjs
    {"name": "links.mjs", "link": "links/links.mjs", ...},        # symlink bin/links.mjs → links/links.mjs
]
```

and `zim_context_compile.py` analogously returned
`runtime_artifact_bin("zim/install.mjs", "zim/install.mjs")`. So the Sep 13
08:06 render of `zim.opt.pb` legitimately landed **real files** at
`bin/links/links.mjs` (the 31460-byte links bundle, 887 lines at the time) and
`bin/zim/install.mjs` (67735 bytes, 1761 lines) — plus `bin/config/command.mjs`
and `bin/config-remote.mjs` from the same era.

The unification commit flipped the *same paths* to aliases:
`links_runtime_bins` now returns
`compfuzor_runtime_bins("links/links.mjs", "links.mjs")`
([`runtime_bundles.py:57-64`](/library/filter_plugins/runtime_bundles.py#L57-L64))
— `link: compfuzor-runtime.mjs` symlink claims — and
[`zim_context_compile.py:114`](/library/filter_plugins/zim_context_compile.py#L114)
claims the `zim/install.mjs` alias.

Apply-side, the two claims travel different tasks:

- raw copy → [`bins.tasks:73-83`](/tasks/compfuzor/bins.tasks#L73-L83), `copy`
  module: file→file overwrite, **succeeds** (hence today's fresh
  `compfuzor-runtime.mjs`);
- alias → [`bins_link.tasks:2-15`](/tasks/compfuzor/bins_link.tasks#L2-L15),
  `file: state=link` with **no `force`**: symlink→symlink retarget
  **succeeds**, file→symlink **fails** with ansible's "refusing to convert from
  file to symlink".

That is exactly the observed asymmetry: sibling `bin/links.mjs` was already a
symlink (old world: `links.mjs → links/links.mjs`), so it re-targeted cleanly to
`compfuzor-runtime.mjs`, while `bin/links/links.mjs` and `bin/zim/install.mjs`
were real files and refused. `bin/config/command.mjs` and `bin/config-remote.mjs`
(`config_compile.py:256`,
[`config_context_compile.py:182`](/library/filter_plugins/config_context_compile.py#L182))
are the same failure class still waiting in that deployment. With a `with_items`
loop, the first refused conversion fails the task and the host, so remaining
aliases are skipped — consistent with more stale files surviving than the two
reported.

Notably this is a *deliberate* gap, not an oversight: the repo constitution
(AGENTS.md) holds that pruning stale or undeclared artifacts is outside
Compfuzor's scope — cleanup is meant to be explicit. The playbook declares the
symlink but has no mechanism to disown the predecessor file. Candidate
mechanisms already exist: the `BINS_ABSENT` tombstone list
([`bins.tasks:14-23`](/tasks/compfuzor/bins.tasks#L14-L23)).

## 6. Tensions / unresolved questions

1. **Representation migration has no story.** Copy→symlink flips need either a
   one-shot remediation (manual `rm`/`BINS_ABSENT`) or a policy (force, or
   bins_link adopting stale real files). Each future delivery-model change
   (e.g. anything touching raw claims) will re-hit this.
2. **Experiment twins duplicate ~300 lines of module declarations.** zim2 is a
   full copy of zim's `ZIM_MODULES`; they will drift (a module added to one and
   not the other silently diverges the experiment from production).
3. **Catalog-without-reader** (`/opt/mise-main`): is writing catalog data into
   deployments that have no runtime intended provenance-keeping, or should the
   data contribution be gated alongside the bins?
4. **Old world cannot be switched over until zim-main is repaired**, and
   switching over means re-running the user-scope installers that rewrite
   `~/.zshenv` blocks and the `zimfw.conf` registry link — a user-visible
   cutover that has not been rehearsed outside `.test-agent/` dry-runs.
5. **"zim2" naming** suggests a zimfw replacement; it is not (zimfw still
   compiles `init.zsh`; the runtime owns install/status/import orchestration).
   Naming will mislead future readers of both the repo and the shell.
6. **Flow authority is validated but unused.** All execution evidence is
   contained dry-runs; `execution.authority: "catalog"` has never driven a real
   deployment's install/status on this host.

## 7. Ranked next directions

1. **Remediate `/opt/zim-main` stale bundles (smallest unblock, do first).**
   Either one deliberate `rm` of the four pre-multicall files +
   `ansible-playbook -i 'localhost,' -c local zim.opt.pb`, or better, declare
   them: `BINS_ABSENT: [links/links.mjs, zim/install.mjs, config/command.mjs,
   config-remote.mjs]` in `zim.opt.pb` (mechanism:
   [`bins.tasks:14-23`](/tasks/compfuzor/bins.tasks#L14-L23)), then re-run.
   This converts the production deployment to the multicall layout and retires
   the recurring failure.
2. **Rehearse the cutover, then flip the shell.** With zim-main repaired,
   run zim2's install/status for real (not dry-run), then repoint
   `~/.config/zsh/zimfw.conf` and the `~/.zshenv` blocks to the new world (or
   re-run zim2's user install). Keep a one-line rollback to the old deployment
   since old-world artifacts remain intact until deliberately removed.
3. **De-duplicate the twins.** Extract the shared `ZIM_MODULES` roster (and
   mise common bins) into an included vars file so zim2 = zim + overlay
   (RUNTIME_FLOW_EXECUTION + isolated paths). Preserves the isolation
   *guarantees* (paths/authority) while killing declaration drift.
4. **Settle the catalog gate.** Either document catalog-without-runtime as
   intended (audit trail for deployments like mise-main) or gate
   `etc/compfuzor-runtime/` contribution on the same `_runtime_present` /
   flow-execution condition as the bins
   ([`gen_runtime_catalog.tasks:21-36`](/tasks/compfuzor/gen_runtime_catalog.tasks#L21-L36)).
5. **Live-validate flow authority on one real deployment.** After 1-2, let
   `compfuzor-flow.sh install` drive zim-main's install flow once, exercising
   the containment hardening (`kmykxtuxyxsv`, `umyymprrvuoq`, `lktmymmtpvll`)
   outside `.test-agent/`, before considering the runtime effort complete.

## Cross-references

- [`doc/config/README.md`](/doc/config/README.md) — entry point for the
  configuration runtime; mental model of controller→spec→runtime split and the
  three implementation environments table.
- [`doc/config/log.md`](/doc/config/log.md) — deployment log with the exact
  flow-execution hardening history and the zim2/mise2 "isolated copies"
  rationale (2026-09-13/14 entries).
- [`doc/config/consumer-toolkit.md`](/doc/config/consumer-toolkit.md) — current
  config command surface, contexts, copy/link representations, Zim workflow.
- [`doc/config/simplification.md`](/doc/config/simplification.md) — candid
  account of remaining accidental complexity this effort attacks.
- [`design/config-anneal/use-cases0.glm53.md`](/design/config-anneal/use-cases0.glm53.md)
  and [`use-cases1.glm53.md`](/design/config-anneal/use-cases1.glm53.md) — the
  survey that motivated "one reusable runtime"; L115 covers the
  install-zim-context consumer bridge.
- [`design/config-anneal/effect-design0.glm53.md`](/design/config-anneal/effect-design0.glm53.md)
  — architecture draft for the multicall runtime, invocation-chain dispatch,
  and a proposed domain-grouped `files/runtime/` layout (largely realized).
- [`design/config-anneal/execution-model0.gpt6.md`](/design/config-anneal/execution-model0.gpt6.md)
  — annealed model for attributed contributors, flows, and cross-plane
  suppression; generalizes `origin_subsystems` (L179-198).
- [`design/config-anneal/catalog-review0.gpt6.md`](/design/config-anneal/catalog-review0.gpt6.md)
  / [`catalog-review1.gpt6.md`](/design/config-anneal/catalog-review1.gpt6.md)
  — review waves that shaped `runtime_catalog.py` and workflow materialization.
- [`design/config-anneal/flow-execution-review0.gpt6.md`](/design/config-anneal/flow-execution-review0.gpt6.md)
  and [`simplification-assessment0.gpt6.md`](/design/config-anneal/simplification-assessment0.gpt6.md)
  (L164 anticipates exactly this `bin/links/links.mjs → bin/compfuzor-runtime.mjs`
  migration) — the review wave this assessment lands alongside.
- [`doc/arch.md`](/doc/arch.md) and [`doc/subsys.md`](/doc/subsys.md) — the
  subsystem contract, `bins_generated` merge semantics, and
  `origin_subsystems` attribution vocabulary the catalog inherits.
- [`library/README.md:193-194`](/library/README.md#L193-L194) — filter
  signatures for `links_runtime_bins`/`links_runtime_dirs`.
- [`design/install-context/systemd-links0.solx.md`](/design/install-context/systemd-links0.solx.md)
  — the LINKS representation seam (copy vs link) that bins_link applies at
  deploy time; sibling tension to this migration.
