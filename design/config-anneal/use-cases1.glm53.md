---
type: UseCaseSurvey
title: The ordinary majority of Compfuzor install and link behavior
description: Quantitative and case-by-case survey of regular playbooks and the generated action pipeline, complementing use-cases0 with an acquisition/materialization/publication/activation/observation matrix and tracer recommendations.
resource: /design/config-anneal/use-cases1.glm53.md
tags: [compfuzor, bins, links, install, publication, status, action-taxonomy, composition]
status: draft
generated: { by: model:glm-5.3-max, at: 2026-09-13 }
verified: { by: unverified }
stale_after: 2026-10-13
sources:
  - id: wave0
    resource: /design/config-anneal/use-cases0.glm53.md
    title: Exceptional-domain use cases (Zim, Mise, systemd, startup files, LINKS)
  - id: bins-doc
    resource: /doc/bins.md
    title: Bin compositors and composers
  - id: subsys-doc
    resource: /doc/subsys.md
    title: Subsystem architecture and the action runner
  - id: pipeline
    resource: /tasks/compfuzor.includes
    title: The generated pipeline order
  - id: common-vars
    resource: /vars/common.yaml
    title: Subsystem contribs and directory bases
---

# The ordinary majority of Compfuzor install and link behavior

## What's up

[use-cases0](/design/config-anneal/use-cases0.glm53.md) surveyed the
exceptional domains — Zim, Mise, systemd publication, shell startup files,
durable LINKS — and derived pressures from them. This second wave looks at the
opposite end: the boring majority. What does an ordinary Compfuzor playbook
declare, what does the generator pipeline actually produce for it, and what
does its generated `install.sh` really do? The hypothesis to test: the
exceptional domains are exceptional precisely because they moved effects into
a runtime, while the ordinary majority still performs its effects at
**render time** inside Ansible, with publication reduced to a hand-rolled
`ln -sfv`.

Research prompt for this wave: *describe what "install" concretely means
across a broad sample of regular playbooks, find the recurring effect clusters
that already have multiple non-exceptional consumers, and pick tracer
migrations that would let an action taxonomy and structured composition grow
out of ordinary behavior instead of Zim's shape.*

## The ordinary majority, quantitatively

772 top-level playbooks. Suffix distribution: 427 `.src.pb`, 54 `.opt.pb`,
37 `.etc.pb`, 37 `.srv.pb`, 13 `.user.pb`, 11 `.repo.pb`, 8 `.pkg.pb`,
4 `.deb.pb`. Declaration usage (count of playbooks):

| Declaration | Playbooks | Share of 772 |
|---|---:|---:|
| `REPO` | 435 | 56% |
| `BINS` | 388 | 50% |
| `PKGS` | 198 | 26% |
| `ENV` | 159 | 21% |
| `ETC_FILES` | 121 | 16% |
| `APT_REPO` | 36 | 5% |
| `LINKS` | 34 | 4% |
| `GET_URLS` | 26 | 3% |
| `SYSTEMD_SERVICE/UNITS/SERVICES` | 27/20/25 | ~3% |
| `TOOL_VERSIONS` | 19 | 2% |
| `USERMODE` | 15 | 2% |
| `CONFIGS` | 9 | 1% |
| `CONFIG_CONTEXTS` | 1 | 0.1% |

Generated leaf names under `BINS` (top-level playbooks): **212 `build.sh`**,
**112 `install.sh`** plus 82 `install-*` and 38 `install-user.sh` (~232 total
install-prefixed), 8 `status-*`, 6 `run.sh`, 4 `setup.sh`, 4 `config.sh`,
2 `apply-*`, and a ~20-name tail (`stamp.sh`, `use.sh`, `dev.sh`, `clean.sh`,
`backup.sh`, …) that no compositor recognizes. `run: true` appears in 60
playbooks; every `exec:`-shaped bin (no `dest`) also auto-runs during the
playbook ([`bins_run.tasks` L9-L22](/tasks/compfuzor/bins_run.tasks#L9-L22)).

So the modal playbook is: **clone a repo, build it with a subsystem generator,
publish the binary into `/usr/local/bin` by symlink, maybe add packages, an
env file, an ETC file, and a systemd unit**. CONFIGS at 9 users (8 without
contexts) and LINKS at 34 are niche; Zim is genuinely the only context
declarer; `apply` is a registered action with two users.

The pipeline order
([`tasks/compfuzor.includes`](/tasks/compfuzor.includes)) is the existing
generic sequencing: variable synthesis and all `gen_*` generators first, then
repositories ([L129](/tasks/compfuzor.includes#L129)), then filesystem —
base dirs, `fs_hierarchy` materialization
([L151](/tasks/compfuzor.includes#L151)), the LINKS plan write
(`link_plan.tasks`, [L160](/tasks/compfuzor.includes#L160)), repo/env/tgz/zip
downloads, `bins.tasks` materialization ([L191](/tasks/compfuzor.includes#L191)),
bin symlinks ([L193-L195](/tasks/compfuzor.includes#L193-L195)) — then extras:
apt repos ([L205](/tasks/compfuzor.includes#L205)), packages
([L207](/tasks/compfuzor.includes#L207)), **`bins_run` after packages**
([L213](/tasks/compfuzor.includes#L213)), a delayed `postRun` bins_link pass
([L222-L225](/tasks/compfuzor.includes#L222-L225)), and the systemd thunk last
([L242](/tasks/compfuzor.includes#L242)). Ordering exists; it is playbook-phase
ordering, not a runtime plan.

## The surveyed cases

Fourteen playbooks across families. Per case: end state, declarations,
generated/runtime actions, primitive effects, ordering, scope/privilege,
status, bypass, convergence, and whether copy/link/block/assembly is
**ownership** (a durable declared relationship), **representation** (a
selectable healthy form), or **implementation detail** (untracked means).

### A. Source build → global bin (the modal case)

**`jujutsu.src.pb`** — end state: `jj` binary in `/usr/local/bin`, TOML config
fragments linked into `~/.config/jj/conf.d/`. Declarations: `REPO`, `RUST:
True`, `RUST_BIN: jj`, two `ETC_FILES`, one hand-written
`install-config.sh` ([L19-L26](/jujutsu.src.pb#L19-L26)) that `mkdir -p`s the
conf.d and loops `ln -sfv` over `etc/*.toml`. Generated:
`build-rust.sh`/`install-rust.sh`/`install-rust-user.sh` from the rust
subsystem ([vars/common.yaml L375-L459](/vars/common.yaml#L375-L459)).
Effects: `cargo build --release` at render time via `run:`; publication is
`ln -sfv target/release/jj $GLOBAL_BINS_DIR/jj` — or `cp + chmod 0755` when
`RUST_COPY=true` for daemons that cannot traverse the checkout symlink
([L410-L441](/vars/common.yaml#L410-L441)). Scope: system destination via
`GLOBAL_BINS_DIR` (`/usr/local/bin`, [L8](/vars/common.yaml#L8)); under
USERMODE it becomes `~/.local/bin` ([L55](/vars/common.yaml#L55)). Status:
none. Bypass: `bypass: ["BUILD","RUST"]` / `["LINK","RUST"]` guards.
Convergence: `ln -sfv` and cargo are naturally convergent; the conf.d loop
never removes stale links. The conf.d farm and the global link are both
**implementation detail**; RUST_COPY shows the same publication point already
needs a *representation* choice (link/copy) made ad hoc.

**`atuin.src.pb`** — the richest ordinary case: `RUST_ALL: True`, MSRV-pinned
`TOOL_VERSIONS`, two ordered user units via `SYSTEMD_ROOTS`
([L39-L60](/atuin.src.pb#L39-L60)), a ZIM_MODULES emergency fragment, a
`status-atuin.sh` drift reporter, and a managed-config bin
`install-atuin-config.sh` ([L96-L136](/atuin.src.pb#L96-L136)). Effects worth
naming: block-in-file with a **section anchor** (`-a '^\[daemon\]' -C file`),
**seeding from an upstream generator** (`atuin default-config > "$CFG"` when
empty), stdin blocks (`-i -`), and **deliberate absence** — an unset
`ATUIN_SEARCH_MODE` *removes* the managed block because an unmanaged value is
a local override that must not be clobbered
([L125-L133](/atuin.src.pb#L125-L133)). Status: a dedicated reporter covering
unit links, enablement, socket/config agreement, block integrity, daemon
identity. The blocks here are **ownership** in everything but a manifest: they
claim named regions of a foreign file with presence policy.

**`opencode.src.pb`** — the everything-ordinary case: bun+nodejs build
subsystems, a jj-remote checkout, generated passwords, a large `ENV`/`ENV_LIST`
surface, user-scope units, `CONFIGS opencode.json` with `json-deep-merge`
over `base.json` + `etc_d/*.json` + remote `mcp/*.json`
([L335-L345](/opencode.src.pb#L335-L345)), and STATUSES. Assembly output is
consumed in place by the deployed service — canonical-only CONFIGS with no
consumer publication at all. Assembly here is the **owner** of the service's
config identity; delivery is not even needed.

### B. Acquisition by download or package

**`deno.opt.pb`** — `GET_URLS` fetches an installer script; `install.sh`
(`run: True`) executes it with `DENO_INSTALL=$DIR`, then `ln -sf` into
`GLOBAL_BINS_DIR` ([L11-L17](/deno.opt.pb#L11-L17)). Acquisition and
publication fused in one authored bin; idempotent by upstream installer
convention; no status; bypass via `BINS_RUN_BYPASS`. The final link is
**implementation detail**.

**`rustup.opt.pb`** — `GET_URLS` fetches `rustup.sh`; a `build.sh` (exec
shaped, so render-run) runs `sh rustup.sh -y` ([L11-L15](/rustup.opt.pb#L11-L15)).
"build" here means *acquire a toolchain*: the name describes compilation, the
semantics are installation-by-vendor-script.

**`ripgrep.opt.pb` / `bubbleupnp-server.deb.pb`** — download a `.deb` and
`apt: deb:` it, with a raw post-include task
([ripgrep L8-L11](/ripgrep.opt.pb#L8-L11)). Acquisition delegated to apt with
Conffile semantics owned by dpkg; no compfuzor publication, status, or bypass
at all — the effect lives outside the BINS surface entirely.

**`mise.repo.pb` / `apt-repos.pb`** — two generations of the same job:
`mise.repo.pb` declares `APT_REPO`/`APT_KEYRING_URL` declaratively (compiled
by `gen_apt`/`apt.tasks`, which downloads keys, dearmors, templates sources,
and **links them into `/etc/apt/sources.list.d` with `become: True`**
([apt.tasks L38-L47](/tasks/compfuzor/apt.tasks#L38-L47))); `apt-repos.pb` is
the pre-compfuzor hand form (sudo copy of `.list` files). The apt lane shows
the recurring shape in miniature: materialize under `DIR`, then expose by
symlink into a system directory, privileged, no status, no runtime artifact.
The exposure link is **ownership**-flavored (it is the declaration's whole
point) but has no record, strategy, or observation.

**`pkgs.tasks`** — plain `apt: state={{APT_INSTALL}}` over merged
`PKGS`/`PKGSET` with `become` ([L1-L12](/tasks/compfuzor/pkgs.tasks#L1-L12));
`pkgs-devel.pb` shows the legacy pre-generator style (raw `apt: pkg=$item`).
Packages are the one acquisition family with full convergence and no
compfuzor-side status; drift is delegated to apt itself.

### C. ETC materialization + assembly consumed in place

**`locales.pb`** — materializes `DIR=/etc/locale.gen.d` files through the
FILES family, assembles `/etc/locale.gen` with a `concat` CONFIG
([L11-L16](/locales.pb#L11-L16)), then **activates** with a raw
`- shell: locale-gen` task ([L20](/locales.pb#L20)) and a chmod. Activation is
a controller-time shell call with no bypass token, no status, and no runtime
identity. Assembly owns the file's content; nothing is published anywhere —
the consumer is the next `locale-gen`.

**`interception-tools.srv.pb`** — same pattern for a service:
`SYSTEMD_EXEC` reads the assembled `{{ETC}}/interception.yaml` directly
([L9](/interception-tools.srv.pb#L9)); `CONFIGS interception.yaml` is a
`concat` with no dir/name override ([L26-L28](/interception-tools.srv.pb#L26-L28)).
Assembly output consumed in place by a unit — zero publication, zero extra
representation. This is the *ordinary* version of what Zim's canonical context
formalized.

**`amp.opt.pb`** — `NPM: '@sourcegraph/amp@latest'` (global-mode npm: a
generated `install-npm.sh` running `pnpm install -g $(cat etc/npm.txt)`
([vars/common.yaml L965-L972](/vars/common.yaml#L965-L972))) plus a
`json-deep-merge` CONFIG for settings assembled from local and remote inputs
([L16-L24](/amp.opt.pb#L16-L24)) — assembled canonically and never published:
donor-ready assembly with no consumer today.

**`mcp-cli.src.pb`** — bun build, then declarative global-bin publication
via a BINS link record with `global: True` and `phase: postRun`
([L24-L26](/mcp-cli.src.pb#L24-L26)) — the *only* sampled case using the
declarative `bins_link_global` lane rather than a hand `ln`. And a hand
`install-user.sh` that does `mkdir -p ~/.config/mcp; ln -s
$(pwd)/etc/mcp_servers.json ~/.config/mcp/mcp_servers.json`
([L27-L31](/mcp-cli.src.pb#L27-L31)): **publication of an assembled CONFIG
output by hand-written symlink** — the exact operation `config-publish.sh
--strategy link` exists to perform, and the strongest small candidate to
become the second `CONFIG_CONTEXTS` declarer.

### D. Exposure links and durable LINKS records

**`termit.pb`** — mapping-form `LINKS`: two whole-file exposures
(`{{ETC}}/rc.lua.example.gz` → `/usr/share/doc/termit/…`, and an alternatives
claim `/etc/alternatives/x-terminal-emulator` → `/usr/bin/termit`
([L9-L12](/termit.pb#L9-L12))). **`xdg-dirs.pb`** — a record-form `LINKS`
exposing the env file as `user-dirs.defaults` ([L8-L10](/xdg-dirs.pb#L8-L10)).
Both are controller-time exposures through the LINKS plan; scope adapts with
`USERMODE` (`/etc/xdg` ↔ `~/.config`).

**`k3s.srv.pb` / `wg.srv.pb`** — durable ownership records: k3s aliases its
`ETC`, `VAR` data dir, and a config template into `/etc/rancher/k3s` and
`/var/lib/rancher/k3s` ([L17-L22](/k3s.srv.pb#L17-L22)); wg exposes
`{{ETC}}/wg0.conf`-style files. These compile to `links.json` v2 via
`gen_links.tasks` ([L1-L16](/tasks/compfuzor/gen_links.tasks#L1-L16)), deploy
the `links.mjs` runtime, and gain `install-link-records.sh` + `status-links.sh`
([L18-L31](/tasks/compfuzor/gen_links.tasks#L18-L31)). This is the full
lifecycle: **ownership** with strategies, policies, sudo routing, status, and
audit — and it is the rare (4%) form.

### E. User-scope assembly, no contexts

**`screen.user.pb`** — `CONFIGS .screenrc` with `concat` over a `.screenrc.d`
glob, output to `$HOME` ([L10-L17](/screen.user.pb#L10-L17)).
**`clickpad.user.pb`** — same shape for `~/.xinitrc` from `.xinitrc.d`
([L14-L20](/clickpad.user.pb#L14-L20)). These are context-free CONFIGS: the
recipe's `dir`/`name` hard-binds the consumer, assembly runs at render, and
there is no runtime surface, status, or strategy. They are the living
justification for contexts (a consumer binding should be data, not recipe
fields) and the cheapest possible adopters.

### F. The archaeology specimen

**`dovecot.pb`** — packages, ETC files/dirs, a `concat` CONFIG for an lmtp
conffile ([L28-L31](/dovecot.pb#L28-L31)), plus a belt of bespoke tasks: a
`linkdir.includes` mass-link of distro conf.d ([L56](/dovecot.pb#L56)), `test
-e || ln -s` for pems, `cp -aurv` for modified conffiles, and two `lineinfile`
surgical edits into shared conffiles ([L70-L71](/dovecot.pb#L70-L71)). Every
problem family in this survey appears here in hand-rolled form: adoption of
distro state, whole-file replacement, and line-level merge — all invisible to
status and bypass. Not a first tracer, but the reference for what the
vocabulary must eventually be able to say.

## Answers

### 1. What does `install` mean across Compfuzor today?

At least six concrete meanings share the word:

1. **Publication by symlink** — `install-go.sh`, `install-rust.sh`,
   `install-bazel.sh`, `install-cmake.sh` are all `ln -sfv` into
   `GLOBAL_BINS_DIR` (with rust's copy variant). Nothing is acquired or
   activated; an already-built artifact is exposed.
2. **Acquisition** — `install-npm.sh` runs `pnpm install -g`; `deno`'s
   `install.sh` runs a vendor installer; `rustup`'s "build" does the same.
3. **Registration with an external manager** — `install-nodejs.sh` runs
   `pnpm link -g`; `install-rust-user.sh` runs `cargo install --path .`
   (which *also builds*: the one place the name means build+publish).
4. **Aggregate composition** — bare `install.sh`/`install-user.sh` run
   children in order; on the Zim host it means the complete domain install.
5. **Activation** — `install-unit.sh` publishes, reloads, enables, starts.
6. **Adoption/anything** — `install-config.sh` (jujutsu) publishes config
   fragments; `install-bash-user.sh` inserts managed blocks; dovecot's
   install-shaped tasks copy and patch.

Additionally, the *time* of `install` varies silently: bins with `run: true`
or `exec:` run during the playbook (after `pkgs`, per the pipeline order),
while compositor-invoked installs run later on the operator's clock. The word
survives because every variant ends in "the declared thing is present and
usable"; the *effect*, *phase*, and *privilege* differ every time.

### 2. Which action names recur, and where do they misdescribe?

`build` (~232) and `install` (~232) dominate; `apply` is registered but has
two users; `status` exists as leaf names but composes only through the
STATUSES lane; `run`/`setup`/`config`/misc (~25 names) compose not at all.
Misdescriptions:

- `install-X.sh` that only links (go/rust/bazel/cmake) — should say
  *publish*.
- `build.sh` that auto-runs at render (`run: true`, `exec:`) — it is the
  render-phase *acquire+compile* step; the name hides that invoking the
  compositor later does not re-run it.
- Same-prefix different-semantics pairs: `install-npm.sh` (acquire) vs
  `install-nodejs.sh` (register) vs `install-rust.sh` (publish) vs
  `install-rust-user.sh` (build+install) — one verb, four lifecycles.
- `install-user.sh` is simultaneously the generated scope compositor name and
  a common authored leaf name; the `bins_generated` merge preset fuses them
  (an authored `install-user.sh` gains composed children — mise's lists
  `install-bash-user.sh`). The name carries both "I am an installer" and "I
  am the user-scope aggregate".
- `install-rust-user.sh: compose: false` (atuin L94-L95) is the only sampled
  BINS-level composition opt-out — vocabulary that exists but is nearly
  unused outside Zim/systemd.

### 3. LINK declarations vs LINKS records vs ad-hoc `ln`

| | mapping/record `LINKS` via `gen_links` | controller exposures (env links, apt, ETC `exposure_root`) | ad-hoc `ln` in BINS |
|---|---|---|---|
| Lifecycle | durable `links.json` v2, runtime apply/status/audit/remove | render-time `file: state=link`, re-evaluated each render | whatever the script does |
| Composition | `install-link-records[-user].sh` lane, `compose:` flag | none (side effect of materialization) | none (inside a bin body) |
| Status | `status-links.sh` rows, representation-aware | none | none |
| Ownership | declared record with policy/strategies/sudo routing | implicit, one-shot, existence-guarded | none — pure implementation detail |

The majority form is the *third* column: dozens of hand `ln -sfv` (jujutsu
conf.d, mcp-cli user link, deno, dovecot pems, every subsystem global-bin
installer). The middle column is the standard for ETC-family exposure (the
`fs_hierarchy` exposure link, apt sources, `env.NAME` into `PREFIX_DIR`
[fs_env.tasks](/tasks/compfuzor/fs_env.tasks)). The first column is the only
one with a real lifecycle and is used by 4% of playbooks.

### 4. Which reusable effects already have ≥2 non-Zim consumers?

- **Global-bin publication** — go, rust (link+copy variants), bazel, cmake,
  nodejs (`pnpm link -g`), npm-global, plus the declarative
  `bins_link_global` lane (`global: True`, postRun phase) used by mcp-cli.
  ~10 hand implementations + 1 declarative path, two representations needed
  (symlink default, copy for daemons under `ProtectHome=`), privilege via
  destination path, **zero status**. The single strongest extraction
  candidate in the repo.
- **Managed blocks** — atuin (anchored, seeded, presence-policy), mise,
  zsh.etc, kitty, rg, tmux, Zim loaders. Atuin adds requirements beyond
  wave 0's provider list: section anchoring, seed-from-generator, and
  deliberate-absence-as-override.
- **Env emission + exposure** — `env`/`env.export` rendering with
  `ENV`/`ENV_LIST`/`ENV_PRIO` resolution and the `PREFIX_DIR` link, 159+ ENV
  consumers; one implementation, heavily reused, no drift story.
- **ETC-family materialization** — the `fs_hierarchy` writer family behind
  `ETC_FILES`/`DIRS`/`FILES`/`VAR_DIRS` (121 users), including json/raw/src
  variants and `once`.
- **Aggregate status** — `status.sh` with baked reporter lists, string vs
  structured `{name, args, exit2: error}` records
  ([status.sh L15-L25](/files/status/status.sh#L15-L25)); consumers: kernel
  reporters, status-dirs, STATUS_PROC (mainpid-env, exe-current), links,
  zim/mise, atuin.
- **Version pins** — `TOOL_VERSIONS`/`MISE_VERSIONS` rendering + repo-root
  link + `mise install` (19 TOOL_VERSIONS users; rust build even invokes
  `links.mjs apply --id '*/.tool-versions,*/mise.toml'` itself,
  [vars/common.yaml L379-L381](/vars/common.yaml#L379-L381) — a subsystem bin
  calling the LINKS runtime as a provider, the same shape as
  `install-unit.sh`).

### 5. Best tracer migrations for action taxonomy and structured composition

(Also the recommendation section below.)

### 6. What regular cases contradict or constrain wave 0's vocabulary

- **Render-time is the norm.** Wave 0's action/effect vocabulary was derived
  from runtime-dispatching domains. The ordinary majority performs
  acquisition, build, materialization, and most publication *during the
  playbook*; only publication/activation/observation have a meaningful
  post-render life. An action taxonomy must therefore carry a *phase*
  dimension (render vs operator) explicitly — the current system encodes it
  only through `run:`/`exec:` accidents.
- **`install-rust.sh` vs `install-rust-user.sh`** quantitatively confirms
  wave 0's negative control: same domain, scoped naming, genuinely different
  operations (publish-existing vs cargo-build-and-install). Scoped copies of
  a name are not one parameterized action.
- **Two privilege regimes coexist.** Ansible `become` (via `become_calc`
  path probing at render) for controller effects vs `links.mjs` sudo routing
  (auto/always/never) for runtime effects. Wave 0 invariant 8 ("privilege
  only through explicit routing") is true, but the routing is split across
  two worlds any unified runtime must name.
- **Assembly-consumed-in-place is ordinary** (locales, interception-tools,
  opencode), not just Zim's canonical concept — consumer-binding-as-data
  (contexts) would serve them, but none of them need runtime selection today;
  their binding is static. Contexts must stay useful with exactly one
  declared consumer.
- **Blocks carry presence policy, not just bytes** (atuin): an absent managed
  block can be the *declared* state when a local override wins. Wave 0's
  block provider spec needs an anchor model and an absence/override contract
  added to its six requirements.
- **Observation is opt-in and rare.** Wave 0's "every effect should have an
  observation counterpart" intuition, applied to the ordinary majority,
  would be a massive lift: most playbooks have no status at all, and the
  honest framing is that observation coverage is generator-driven with
  adoption gaps — the taxonomy should make status *cheap to attach* to a
  declared effect, not mandatory.

## Matrix: cases by verb instead of domain

A = acquisition, M = materialization, P = publication, Act = activation,
O = observation. `●` performed, `○` possible but absent, `—` not applicable.
Cells name the mechanism.

| Case | A | M | P | Act | O |
|---|---|---|---|---|---|
| jujutsu.src | ● cargo build (render) | ● ETC_FILES | ● hand `ln -sfv` (global bin, conf.d) | — | ○ |
| atuin.src | ● cargo build | ● ETC_FILES, pins | ● hand ln (global bin), managed blocks ×2 | ● systemd user units (socket→service order) | ● status-atuin.sh |
| opencode.src | ● bun/pnpm build | ● ETC_FILES, env, passwords, CONFIGS json-merge | ○ (consumed in place) | ● user units + timer | ● STATUSES |
| deno.opt | ● vendor installer (render `run:`) | — | ● hand ln (global bin) | — | ○ |
| rustup.opt | ● vendor installer ("build.sh") | — | — (rustup self-manages) | — | ○ |
| ripgrep.opt | ● apt deb (raw task) | — | — (dpkg owns) | — | ○ |
| mise.repo | ● apt repo (declarative lane) | ● keys/sources under ETC | ● exposure link (`become`) | ○ apt update | ○ |
| locales | — (dpkg) | ● FILES family | — (in place) | ● `locale-gen` raw shell | ○ |
| amp.opt | ● pnpm -g (generated) | ● ETC json, CONFIGS json-merge | ○ (canonical only) | — | ○ |
| mcp-cli.src | ● bun build | ● ETC mcp fragments, CONFIGS json-merge | ● declarative `global: True` postRun link; hand `ln` to `~/.config` | — | ○ |
| termit/xdg-dirs | — | ● ETC_FILES/env | ● LINKS exposure records | — | ○/● (links status if runtime deployed) |
| k3s/wg.srv | ○ (own installer) | ● ETC/VAR trees | ● LINKS v2 records (durable, policies) | ● downstream service | ● status-links.sh |
| screen/clickpad.user | — | ● ETC/FILES + CONFIGS concat | — (dir/name hard-bound) | — (sourced by shell) | ○ |
| interception-tools.srv | ● PKGS | ● ETC yaml + CONFIGS concat | — (consumed by `SYSTEMD_EXEC`) | ● systemd service | ○ |
| dovecot | ● PKGS | ● ETC_FILES + CONFIGS concat | ● bespoke mass-link + cp | ● (distro service) | ○ (lineinfile edits invisible) |
| *(contrast: zim.opt)* | ● module clones (cache build) | ● CONFIGS + contexts spec | ● input link farm, publish, blocks, registry | ● loader blocks + cache rebuilds | ● config/zim/aggregate rows |

Reading the matrix: **A and M are overwhelmingly render-time; P splits three
ways (hand detail / controller exposure / durable records); Act is mostly
delegated to systemd or raw shells; O is the rarest column** — the exact
inversion of wave 0's runtime-centric cases.

## Recommended tracers (3-5) for the install-composition/action-taxonomy conversation

1. **Global-bin publication lane** (jujutsu/deno/atuin + subsystem
   installers). One declarative publication record — strategy link|copy
   (RUST_COPY is the proven second consumer), destination root from scope
   (`GLOBAL_BINS_DIR` ↔ USERMODE local bin), postRun phase, privilege
   routing, and a status row ("binary present, correct referent, which
   representation"). Retires ~10 hand `ln`s, unifies the one effect with the
   most consumers in the repo, and forces the taxonomy to name publish-as-a-
   first-class-action distinct from install.
2. **`mcp-cli.src.pb` per-user publication of an assembled CONFIG output**
   (hand `ln -s` → `config-publish.sh --strategy link` under a declared user
   context). The smallest honest second `CONFIG_CONTEXTS` declarer — answers
   wave 0's gating questions 7 (complete-install ownership) and gives
   contexts their non-Zim adopter without touching privilege.
3. **`jujutsu.src.pb` conf.d farm** (hand loop → declarative input sync, or
   LINKS records). User-scope, no sudo, immediately comparable to Zim's
   68-link farm at miniature scale; tests whether input-sync vocabulary is
   generally adoptable or Zim-shaped.
4. **Atuin's managed-block pair** as the ordinary pilot for the wave-0 block
   provider: it already exercises anchoring, seeding, stdin, and
   deliberate-absence — the two provider requirements wave 0's list missed.
   Migrating its status to a shared block-health vocabulary (with mise) is
   the second-consumer proof.
5. **`locales.pb` / `interception-tools.srv.pb` activation naming** — the
   smallest test of an explicit activation verb: `locale-gen` is a raw
   controller shell today, and interception-tools shows assembly-consumed-
   in-place as a terminal state. Decide whether activation is always domain
   vocabulary (wave 0's position) or whether controller-phase activation
   needs a bypass/observation token like everything else.

Do not start with dovecot; it is the finish-line specimen that proves the
vocabulary can describe adoption, whole-file replacement, and line-level
merge — families this survey confirms are real but which deserve their own
later wave.

## Cross-references

- [`use-cases0.glm53.md`](/design/config-anneal/use-cases0.glm53.md) — the
  exceptional-domain wave this document complements; its layer table and
  block-provider requirements are extended here by render-time evidence,
  the phase dimension, and atuin's anchor/absence semantics; its gating
  questions 2/3/7 map directly onto tracers 4, 1, and 2.
- [`doc/bins.md`](/doc/bins.md) — compositor hierarchy and action metadata;
  the `install-user.sh` dual-name fusion and the unused `apply` action are
  its open edges.
- [`doc/subsys.md`](/doc/subsys.md) — subsystem contribs, the action runner,
  and the LINKS section defining the durable-record lifecycle this survey
  finds used by only 4% of playbooks.
- [`vars/common.yaml`](/vars/common.yaml) — subsystem-generated
  build/install bins (go L251-L268, nodejs L274-L322, rust L375-L459,
  npm L965-L972) and directory bases (L7-L59) that define ordinary scope.
- [`tasks/compfuzor.includes`](/tasks/compfuzor.includes) — the pipeline
  order that is today's only generic sequencing.
- [`doc/config/consumer-toolkit.md`](/doc/config/consumer-toolkit.md) — the
  context machinery tracers 2-3 would adopt; screen/clickpad/locales/
  interception-tools are its undeclared-consumer backlog.
- [`files/status/status.sh`](/files/status/status.sh) — the aggregate
  observation contract tracer 1 should grow a row into.
