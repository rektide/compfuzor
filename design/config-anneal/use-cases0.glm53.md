---
type: UseCaseSurvey
title: Use cases that should shape a reusable compfuzor-runtime
description: Six real or near-term CONFIG/install use cases, layer separation, block-in-file placement, and the pressures and questions that gate annealing CONFIG/install into a reusable runtime.
resource: /design/config-anneal/use-cases0.glm53.md
tags: [compfuzor, config, contexts, zim, mise, zx, block-in-file, links, systemd, bins]
status: draft
generated: { by: model:glm-5.3-max, at: 2026-09-13 }
verified: { by: unverified }
stale_after: 2026-10-13
sources:
  - id: toolkit
    resource: /doc/config/consumer-toolkit.md
    title: Current consumer configuration contract
  - id: simplification
    resource: /doc/config/simplification.md
    title: Deletion-oriented simplification plan
  - id: deployment-log
    resource: /doc/config/log.md
    title: Live Zim/Mise deployment evidence
  - id: command0
    resource: /design/config-context/command0.solx.md
    title: Fixed CONFIG actions over selected contexts
  - id: core-rescope
    resource: /.design/config-user-target/core-rescope0.unknown.md
    title: Core re-scope for contexts, commands, and complete installs
  - id: systemd-links0
    resource: /design/install-context/systemd-links0.solx.md
    title: Systemd unit representations under LINKS ownership
---

# Use cases that should shape a reusable compfuzor-runtime

## What's up

The parent session is annealing CONFIG and install machinery into a reusable
**compfuzor-runtime**. The live system works: Zim and Mise were rendered,
activated, and verified clean on 2026-09-13
([deployment log](/doc/config/log.md#vite-packaged-runtime-cutover)), and the
six fixed CONFIG action commands are deployed over one dispatcher
([consumer toolkit](/doc/config/consumer-toolkit.md#L7-L14)). The standing
constraint for this wave: **the generic CONFIG context interface survives and
advances**. Zim being the only checked-in declarer of `CONFIG_CONTEXTS` today is
not evidence against contexts — the two-context behavior is exercised directly
by generic integration fixtures
([core-rescope0](/.design/config-user-target/core-rescope0.unknown.md#L99-L103))
— but the runtime shape should be justified by more consumers than one.

This document surveys concrete use cases and asks what each one demands of a
reusable runtime: declarations, actions, effects, status, context needs, and
composition needs. It then separates generic effect-library concerns from
CONFIG-specific and domain-specific orchestration, places block-in-file, names
awkward playbooks worth migrating as generalization tests, and ends with design
invariants and gating questions.

Research prompt for this wave, restated: *what do real deployments actually do
at install time, and which of those behaviors recur across domains often enough
to belong in a shared runtime, versus staying domain-local?*

## The six use cases

### 1. Zim host — user-context Zsh assembly (live, the current declarer)

The anchor use case. [`zim.opt.pb`](/zim.opt.pb) declares two recipes
(`zimrc`, `zimenv`) with the `block-in-file` processor, `zsh -dfn "$CONFIG_CANDIDATE"`
validation, remote glob inputs, and `remove_match` legacy-cleanup patterns
([L17-L39](/zim.opt.pb#L17-L39)). It binds them through a `user` CONFIG context
whose outputs are **environment-selected** (`ZIM_CONFIG_FILE` / `ZIM_ENV_CONFIG`
with `ignore` lists for canonical and legacy paths,
[L40-L61](/zim.opt.pb#L40-L61)), and adapts them through `ZIM_CONTEXTS` with
loader/cache/registry paths ([L66-L68](/zim.opt.pb#L66-L68)).

- **Runtime actions**: `config-install.sh` seeds 68 consumer input links,
  assembles both outputs inside one transaction, validates, and atomically
  commits; `install-zim.sh` runs the typed CONFIG install, then projects two
  loader blocks, builds two caches, and applies one registry link
  ([`files/zim/install.ts` L77-L112](/files/zim/install.ts#L77-L112));
  `status-zim.sh` aggregates config health, loaders, caches, and registry
  ([L172-L184](/files/zim/install.ts#L172-L184)).
- **Effects**: input symlink farm under `~/.config/zsh/{zimrc,zimenv}.d`; whole
  assembled outputs at env-bound paths; two managed named blocks in
  `.zshenv`/`.zshrc` installed via block-in-file over stdin with legacy
  `--remove-match` first ([`files/zim/activation.ts` L143-L154](/files/zim/activation.ts#L143-L154));
  mtime-fresh caches; registry symlink applied through an **ephemeral LINKS v1
  manifest** ([L45-L66](/files/zim/install.ts#L45-L66)).
- **Status needs**: 72-row representation-aware status (2 assembly outputs, 68
  input links, 0/1/2 exit contract); per-artifact naming (channel, component,
  path) so a clean run *confirms* rather than merely failing loudly; loader
  byte-compare via `--read` against a re-derived projection
  ([L177-L203](/files/zim/activation.ts#L177-L203)); cache freshness vs config
  mtime.
- **Context needs**: runtime env-binding with precedence (explicit env value →
  ignore-list screen → default), XDG root expansion at runtime rather than
  render time, a reserved `canonical` donor context where only assembly and
  status are meaningful.
- **Composition needs**: `CONFIG_INSTALL_OWNER: zim`
  ([L16](/zim.opt.pb#L16)) so bare `install.sh` runs the complete Zim installer
  once instead of duplicating the generic config installer; typed-bypass
  interaction — when CONFIG install is bypassed, Zim continues from existing
  outputs and otherwise skips *with a reason*, never passing empty config to
  cache construction ([L94-L107](/files/zim/install.ts#L94-L107)).
- **What it proves**: the whole stack. Typed operations beneath the CLI
  (`installContext`, `putInput`, `statusContext` imported by the domain
  adapter), the domain-adapter-over-CONFIG pattern, and the
  skip-with-reason-under-bypass contract.

### 2. Zim contributor → donor promotion → consumer import (live machinery, near-term growth)

Compfuzor's package-exchange convention. Contributor playbooks such as
[`git.etc.pb`](/git.etc.pb#L9-L35) declare `ZIM_MODULES` with inline
`env`/`functions`/`aliases` kinds and receive a scope-neutral
`install-zimfw.sh`. Promotion into the host donor is explicit:
[`install-zim-donor.sh`](/files/install-zim-donor.sh) walks
`etc/zim/<channel>/{active,disabled}` and calls `config-remote.mjs link` per
fragment; consumer import via [`install-zim-context.sh`](/files/install-zim-context.sh)
runs `putInput` per fragment and rebuilds only touched channels
([`files/zim/install.ts` L139-L170](/files/zim/install.ts#L139-L170)).

- **Effects**: fragment files exchanged in a fixed directory convention;
  donor-side links into canonical inputs; consumer-side input entries with
  disabled state; incremental per-channel cache rebuilds.
- **Status needs**: the known gap — a contributor cannot cheaply ask "are my
  fragments promoted?" (named in
  [init0](/.design/zim-generator/init0.gpt56.md#L119)). Promotion state is a
  *relationship* (donor entry ↔ contributor fragment) that no status command
  currently observes.
- **Context needs**: `canonical` as a first-class admin role, not just a
  reserved read-only binding; the donor mutation path is deliberately narrow
  (`putInput` through remote tooling, not `sync-inputs`/`publish`).
- **Composition needs**: contributor installs compose into the **user lane**
  regardless of the host's default context (scope-neutral metadata), showing
  that composition scope is a default, not a boundary.
- **What it tests**: whether "donor administration" stays a Zim protocol or is
  a reusable runtime role (declare fragments → promote → import → rebuild) that
  other assembly domains could reuse.

### 3. Mise + zx contributor toolchain workflow (proposed, partially live)

*Interpretation note:* the specific proposal originates in the parent session;
this reconstruction is from repo evidence. The shape: contributor machines
provision toolchains with mise (deno for block-in-file, node/pnpm, zx for
scripting), driven by per-repo version pins, with shell activation owned by the
Zim `zimenv` channel for Zsh and by independent Bash blocks for Bash.

Live pieces today:

- [`mise.opt.pb`](/mise.opt.pb) installs two Bash activation blocks via
  block-in-file with env-overridable destinations
  ([L59-L71](/mise.opt.pb#L59-L71)), reports their health through
  `block-status.sh` ([L72-L82](/mise.opt.pb#L72-L82)), and sets npm package
  manager settings unconditionally during install ([L48-L58](/mise.opt.pb#L48-L58)).
  Zsh activation is deliberately ceded to the `rektide/zim-mise` module
  ([L23-L26](/mise.opt.pb#L23-L26)), and the systemd ambient-env bridge was
  disabled because an ambient env channel competed with per-deployment env
  ([L5-L15](/mise.opt.pb#L5-L15)).
- [`gen_tool_versions.tasks`](/tasks/compfuzor/gen_tool_versions.tasks) renders
  `.tool-versions` / `mise.toml` into deployment `DIR` and links the pin into
  the repo root when a checkout exists — because mise/asdf resolve versions
  from the *physical* cwd ([L1-L27](/tasks/compfuzor/gen_tool_versions.tasks#L1-L27)) —
  and contributes a `mise install` bin ([L85](/tasks/compfuzor/gen_tool_versions.tasks#L85)).
- [`block-in-file.src.pb`](/block-in-file.src.pb) is the awkward precedent: a
  hand-rolled `.tool-versions` ETC file plus a bespoke `ln -s` in its install
  bin ([L7-L24](/block-in-file.src.pb#L7-L24)), predating the generator.
- [`zx.src.pb`](/zx.src.pb#L7-L11) builds google/zx via `npm install && npm
  link` — a plain source deployment whose toolchain would come from mise.

- **Runtime actions**: `install-user.sh` (blocks + settings), `install-bash-user.sh`
  (blocks only), `mise install` from the generator, repo-root pin links via the
  LINKS records lane.
- **Effects**: managed blocks in `~/.bashrc` / `~/.bash_profile`; whole-file
  pin at `DIR/.tool-versions`; repo-root symlink `REPO_DIR/.tool-versions` →
  DIR file (a LINKS record, `force` default so a repo-owned file is never
  clobbered); global-bin installation (`deno task install:dir` with
  `GLOBAL_BINS_DIR`).
- **Status needs**: block health exists; **settings drift does not** (`mise
  settings set` runs unconditionally); toolchain presence is mise's domain but
  the runtime could observe *pin presence* per checkout.
- **Context needs**: env-overridable destinations (`BASH_RC`, `BASH_PROFILE`);
  notably *no CONFIG context* — the toolkit doc is explicit that Mise does not
  acquire a CONFIG graph ([doc/config/README.md L63-L68](/doc/config/README.md#L63-L68)).
- **Composition needs**: activation blocks must load **once** and early (the
  dual-channel design exists precisely so mise loads exactly once,
  [channels1](/.design/zim-generator/channels1.gpt56s.md#L56-L69)); nothing
  else may assume ambient env from mise.
- **What it tests**: the runtime must keep "independent blocks + shared status
  helper" a first-class shape, not a degenerate case of assembly; and it must
  name where toolchain-pin delivery lives (LINKS records + tool-versions
  generator) so bespoke copies like block-in-file's die.

### 4. Systemd unit publication (live; the accepted boundary case)

The comparison domain that most sharply bounds the anneal. Playbooks declare
`SYSTEMD_UNITS`/`SYSTEMD_SERVICES`/`SYSTEMD_INSTALLS`;
[`install-unit.sh`](/files/systemd/install-unit.sh) resolves strategy
(explicit flag → legacy booleans → compiled record default,
[L38-L69](/files/systemd/install-unit.sh#L38-L69)), **delegates unit
publication to `links.mjs apply --id UNIT_LINK_ID`** when the LINKS manager is
installed ([L75-L101](/files/systemd/install-unit.sh#L75-L101)), falls back to
direct `SUDO_CMD cp/ln` when it is not, then `daemon-reload` and enable/start
with fully-typed unit names ([L104-L129](/files/systemd/install-unit.sh#L104-L129)).
LINKS records for units declare both strategies and `compose: false` so the
later generic records lane neither repeats nor undoes ordered publication
([doc/subsys.md L555-L599](/doc/subsys.md#L555-L599)).

- **Status needs**: LINKS covers publication representation only; manager load
  freshness, enablement, and activation expectations remain an open systemd
  domain status (remaining local issue #2,
  [systemd-links0](/design/install-context/systemd-links0.solx.md#L156-L165)).
- **Context needs**: none — scope bindings select manager/authority/directory
  maps, and the checkpoint explicitly rejects systemd-as-CONFIG-context
  ([L124-L134](/design/install-context/systemd-links0.solx.md#L124-L134)).
- **Composition needs**: subsystem tier (`install-systemd-user.sh`), ordered
  leaves (socket before service in the atuin example,
  [doc/bins.md L134-L151](/doc/bins.md#L134-L151)), `compose: false` exclusion,
  publication bypass authoritative through complete install.
- **What it proves**: the provider pattern — a domain installer calls a shared
  delivery manager with a bounded override, tolerates the manager's absence
  with a documented fallback, and keeps activation ordering domain-local. Any
  "reusable runtime" must support this shape, not replace it with a plan graph.

### 5. Shell-startup migrations: zsh.etc, rg, tmux, kitty (awkward, worth migrating)

A family of hand-rolled startup-file deployments that predate the machinery and
would test/generalize a reusable runtime:

- [`zsh.etc.pb`](/zsh.etc.pb) injects **five managed blocks** into system
  `/etc/zsh/{zshenv,zshrc}` with `become: true`
  ([L119-L128](/zsh.etc.pb#L119-L128)), performs controller-side line edits on
  shared conffiles `/etc/default/useradd` and `/etc/adduser.conf`
  (`dest`/`regexp`/`state` ETC files,
  [L48-L65](/zsh.etc.pb#L48-L65)), and stamps a per-user `conf.d` chain into
  `~/.zshrc` ([L132-L140](/zsh.etc.pb#L132-L140)). Much of its content has
  already migrated to declarative `ZIM_MODULES` kinds — the residue is block
  delivery, line edits, and a system context.
- [`rg.etc.pb`](/rg.etc.pb#L14-L18) pipes an envsubst'd `RIPGREP_CONFIG_PATH`
  export into `~/.zshrc` with a bare block-in-file call — a fragment that
  belongs in the `zimenv` channel vocabulary now.
- [`tmux.etc.pb`](/tmux.etc.pb#L22-L31) hand-rolls the exact stack the runtime
  already provides, *with bugs* (`TMUX_CONF_DIR=` empty, `$TMUX_CONFI_D_DIR`
  typo, `--envsubstr` typo) — symlink loops plus envsubst blocks into
  `$TMUX_CONF`.
- [`kitty.user.pb`](/kitty.user.pb#L11-L15) does `mkdir`/`ln -sf` plus a
  `globinclude` block into `kitty.conf`.

- **What they test**: a **system-scope CONFIG context** (zsh.etc's `/etc/zsh`
  targets need privilege routing CONFIG currently lacks); managed blocks as an
  install *strategy* inside a context rather than ad-hoc shell; input-symlink
  farms generated instead of hand-looped; and whether env-fragment vocabulary
  (rg) becomes donor input instead of bespoke blocks. Each migration is small,
  concrete, and immediately exercises status on real files.

### 6. Durable whole-file ownership: LINKS deployments (live)

The other half of delivery. `pstore.etc.pb` drops a modprobe.d fragment via
ETC_FILES + a system LINKS record ([L237-L249](/pstore.etc.pb#L237-L249));
`motd.etc.pb` links `/etc/motd` with sudo ([L10-L14](/motd.etc.pb#L10-L14));
`vim.user.pb` declares a whole-tree mapping LINK plus two ad-hoc `ln` shell
tasks ([L18-L19](/vim.user.pb#L18), [L27](/vim.user.pb#L27));
`watchwoman.src.pb` maintains a compatibility alias farm of LINKS records.
LINKS v2 owns strategy availability, defaults, compose participation, sudo
routing, and conservative removal
([doc/subsys.md L481-L553](/doc/subsys.md#L481-L553)).

- **Status needs**: representation-aware rows (`link`/`copy`), full visibility
  even for `compose: false` records, audit over the durable manifest.
- **What it tests**: the invariant that CONFIG consumer copy/link operations
  are *not* LINKS declarations — shared effects, distinct ownership contracts
  ([L593-L599](/doc/subsys.md#L593-L599)). A runtime that blurs this regresses.

## Layer separation

What the six cases say about where concerns belong:

| Concern | Belongs to | Evidence |
|---|---|---|
| Atomic copy/link, entry inspection, physical-alias hazards | **Generic effect library** | [`links/delivery.ts`](/files/links/delivery.ts) already shared by CONFIG and LINKS ([L133-L170](/files/links/delivery.ts#L133-L170)) |
| Managed-block project/insert/read/remove/compare | **Generic effect library** (currently ad-hoc) | Zim loaders, mise blocks, zsh.etc blocks, kitty, rg, tmux all shell out to block-in-file; [`block-status.sh`](/files/block-status.sh) is the shared observation |
| Build-validate-commit-rollback transaction | **Generic effect library** | [`config-run.sh`](/files/config-run.sh) staging/backup/rollback ([L175-L238](/files/config-run.sh#L175-L238)) — not config-specific in shape |
| Path selectors, selected-name precedence, status exit contract 0/1/2 | **Generic runtime kernel** | [command0 truth tables](/design/config-context/command0.solx.md#L77-L131) |
| Recipes, processors, input inventory/seed/refresh/enable/disable, canonical donor, contexts | **CONFIG-specific** | [`config_compile.py`](/library/filter_plugins/config_compile.py), [`config/context.ts`](/files/config/context.ts) |
| Loaders, caches, registry, producer protocol, promotion/import | **Domain (Zim)** | adapter deliberately shallow over CONFIG |
| daemon-reload/enable/start; unit directory maps | **Domain (systemd)** | delegated publication + domain activation |
| Activation blocks, settings, toolchain pins | **Domain (mise)** + LINKS/tool-versions generators | negative control against CONFIG-graph creep |
| Ordering between domain steps (publish→reload→enable; config→loaders→caches) | **Domain**, expressed as `compose: false` + leaf order | [systemd-links0](/design/install-context/systemd-links0.solx.md#L60-L66) |

The rule the cases keep confirming: **share effects and selection, never
ownership or sequencing**. The core-rescope direction table already ranked
this ([direction B](/.design/config-user-target/core-rescope0.unknown.md#L503-L515));
the use cases above are the concrete evidence behind that ranking.

## Where block-in-file belongs

Today block-in-file plays four roles at once: an external managed tool
(installed by its own playbook with a mise-provided deno), one of three CONFIG
processor kinds, the de-facto managed-block effect invoked ad hoc by five
domains, and the object `block-status.sh` wraps for observation. Zim even
rebuilt template substitution on top of it
([`activation.ts` L115-L141](/files/zim/activation.ts#L115-L141)) — the
simplification plan already proposes deleting that in favor of the tool's own
`--envsubst` with a namespaced allow-list
([simplification §1](/doc/config/simplification.md#L71-L106)).

**Assessment**: managed blocks are a third delivery representation beside copy
and link — a declared source, a destination file shared with foreign content, a
namespaced block name, a policy, and a byte-exact health contract. That
*effect* belongs in the shared effect library behind a **provider seam**; the
tool remains an external provider, exactly as systemd treats `links.mjs`.
Concretely, a reusable block provider primitive needs:

1. **Resolution**: one bounded resolver — `CONFIG_BLOCK_IN_FILE` env override →
   PATH → declared deployment dependency (mise/zim/zsh.etc already agree on
   this convention informally).
2. **Capability probe**: envsubst (incl. non-recursive + exclusion regex),
   `--read`, `--remove-match`, stdin input — fail with an actionable
   install/rerender message rather than a generic spawn error.
3. **Invocation contract**: argv-array spawn, bytes via stdin or `-i`; defined
   exit semantics distinguishing applied / missing-destination / missing-block.
4. **Projection contract**: one derivation of installed bytes used by both
   install and status (envsubst allow-list, or an upstream render operation),
   replacing Zim's token engine and `block-status.sh`'s temp-file compare with
   a single shared code path.
5. **Refusal parity**: directories and special files are never block
   destinations, matching [`delivery.ts`](/files/links/delivery.ts#L89-L93).
6. **Ownership vocabulary**: deployment-scoped block names (`zim-main-zimrc`,
   `mise-main`) already namespace shared files safely; a collision policy and
   `compose` participation flag would mirror LINKS v2 if blocks ever gain a
   durable tier.

Whether blocks get a **durable record manager** (a LINKS sibling with
`links.json`-style manifest) or stay ad-hoc declarations plus shared status is
a second-consumer question — see gating questions below. Zim's ephemeral
registry manifest ([`zim/install.ts` L45-L66](/files/zim/install.ts#L45-L66))
is the intermediate precedent: manifest semantics, deliberately not durable.

## Effect coverage gaps the runtime should name

Two effect families ship today with **no runtime observation counterpart**,
violating the intuition that every shipped effect has a status:

- **Line edits on shared conffiles** (zsh.etc's `useradd`/`adduser.conf`
  entries) — controller-time only, invisible to `status.sh`.
- **Semantic merges** (`gdm-no-suspend.etc.pb`'s `crudini --merge` into
  `/etc/gdm3/greeter.dconf-defaults` + `systemctl reload gdm`,
  [L32-L40](/gdm-no-suspend.etc.pb#L32-L40)) and settings mutation (mise's
  `mise settings set`).

Either the runtime grows a minimal "declared merge/setting with health" story,
or these are explicitly documented as controller-side effects outside runtime
guarantees. Deciding this deliberately beats the current silence.

## Design pressures and invariants

1. **Contexts survive and advance.** One recipe binds many consumers; `user` is
   the default; selection happens at runtime through one precedence chain, not
   generated filenames. Zim's adapter must remain deletable without touching
   the context core — and the core must gain its second real declarer.
2. **Representations, not preferences.** Matching copy, equivalent link,
   matching local assembly, and (with the block provider) a matching managed
   block are all *healthy* states. Status reports relationship health; the
   effective next-install mode is separate information.
3. **Effects shared, ownership distinct.** LINKS durable records vs CONFIG
   consumer delivery vs ad-hoc blocks may all land bytes through the same
   primitives with different contracts. Never merge the contracts.
4. **Providers are external and resolvable.** Env override → PATH → declared
   dependency; graceful, documented fallback when the provider is absent
   (install-unit.sh's direct-delivery branch is the model). Never vendor a
   reimplementation (Zim's token engine is the cautionary tale).
5. **Domain sequencing beats generic ordering.** `compose: false`, subsystem
   tiers, and leaf order express "publish before reload" without a plan graph.
6. **Observation is never bypassed.** Bypass tiers exist (generation-time vars,
   typed runtime bypass, domain bypass with skip-reason) but status stays
   active and complete under all of them.
7. **No prune, no receipts; conservative removal only when provably managed**
   (byte-equal copy with live source; normalized-target link).
8. **Scope is root defaults, never privilege.** Privilege appears only through
   explicit routing (`--sudo auto|always|never`, `SUDO_CMD` fallbacks). A
   system CONFIG context must not quietly become a sudo path.
9. **Partial success is allowed; status must explain it.** Skip-with-reason
   under bypass, and cross-artifact naming on clean runs, are load-bearing.
10. **The deletion test governs the anneal** ([simplification
    §recommended order](/doc/config/simplification.md#L240-L250)): removing a
    layer must eliminate an interface callers had to understand, not relocate
    complexity.

## Gating questions

1. **Blocks as third strategy**: adopt the block provider seam (resolution,
   capability probe, one projection path) before or after the Zim envsubst
   deletion? Does `block-status.sh` fold into the provider, leaving one block
   health vocabulary for mise, zsh.etc, and Zim loaders?
2. **Durable blocks or ad-hoc?** Three ad-hoc consumers (mise 2 blocks, zsh.etc
   5, Zim 2 loaders) but zero durable ones. Does the second-consumer rule
   justify a `blocks.json`-style manager with `compose` flags, or do ad-hoc
   declarations + shared status suffice? What would change the answer?
3. **System-scope CONFIG delivery and privilege**: migrating zsh.etc's
   `/etc/zsh` blocks needs `become`. Does CONFIG publication grow LINKS-style
   sudo routing (auto/never/always), or do system contexts stay
   assemble-into-canonical + explicit privileged publish?
4. **Startup-file ownership**: is "which shell startup file do I land in"
   (ZDOTDIR, bash_rc, TMUX_CONF) a context dimension the runtime should name,
   or strictly domain vocabulary? Zim answers it with `loader_root`; mise with
   env-overridable vars; tmux with bugs.
5. **Unobservable effects**: line edits, crudini merges, mise settings — grow a
   minimal health story, or declare them outside runtime guarantees?
6. **Toolchain pins**: is `gen_tool_versions` + repo-root LINKS + `mise install`
   the accepted whole answer for the Mise/zx contributor workflow (retiring
   block-in-file.src.pb's bespoke `.tool-versions`)? Where does `mise settings`
   drift observation live?
7. **Complete-install ownership**: `CONFIG_INSTALL_OWNER` is a compile-time
   scalar; core-rescope checkpoint 4 proposed structured BINS invocation
   metadata. Which lands before a second complete-install adopter (a migrated
   zsh.etc? tmux?) appears?
8. **"Runtime" as layer or package**: today four Vite+ bundles (config, zim,
   links, config-remote) deploy beside shell runners. Does compfuzor-runtime
   name the deployed bundle of effect/status/provider modules — a packaging
   boundary — or a new architectural layer? The use cases suggest the former;
   say so explicitly before extraction begins.
9. **Donor administration as a runtime role**: promotion/import status ("are my
   fragments promoted?") is a real contributor need. Zim protocol forever, or a
   named donor-admin role over canonical contexts?

## Cross-references

- [`doc/config/consumer-toolkit.md`](/doc/config/consumer-toolkit.md) — the
  maintained contract every use case above must keep passing; its Zim and
  status sections are the behavioral baseline.
- [`doc/config/simplification.md`](/doc/config/simplification.md) — the
  envsubst and compiler-split deletions are prerequisites for a clean block
  provider seam; this wave depends on their direction.
- [`design/config-context/command0.solx.md`](/design/config-context/command0.solx.md)
  and its [review](/design/config-context/command0-review0.solx.md) — the
  fixed-action surface and truth tables the runtime kernel inherits.
- [`design/install-context/systemd-links0.solx.md`](/design/install-context/systemd-links0.solx.md)
  — the provider/delegation pattern (unit → links.mjs) this survey generalizes;
  also the accepted "not a CONFIG context" boundary.
- [`.design/config-user-target/core-rescope0.unknown.md`](/.design/config-user-target/core-rescope0.unknown.md)
  — the vocabulary (context/scope/action/strategy/phase) and direction-B
  framing this survey's layer table confirms; its checkpoints 4–6 are the
  remaining unimplemented seams surfaced again here.
- [`doc/config/log.md`](/doc/config/log.md) — live-render evidence that the
  Zim/Mise deployments behind use cases 1 and 3 are clean.
- [`.design/zim-generator/channels1.gpt56s.md`](/.design/zim-generator/channels1.gpt56s.md)
  — dual-channel rationale behind "mise loads exactly once", which constrains
  any block/activation composition in use case 3.
- [`doc/bins.md`](/doc/bins.md) — action metadata and subsystem tiers that
  carry the composition needs in use cases 1, 2, and 4.
