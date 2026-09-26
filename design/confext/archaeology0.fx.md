---
type: Design archaeology
title: FS_CONTAINERD → self-contained playbooks → a post-runtime confext builder
description: Session- and history-grounded archaeology of the FS_CONTAINERED/containered-layout changes, the recent self-contained playbook needs, the compfuzor-runtime boundary, and what a build-confext post-runtime flow would inherit from each.
resource: https://github.com/rektide/compfuzor/blob/main/design/confext/archaeology0.fx.md
tags: [compfuzor, confext, sysext, systemd, fs-hierarchy, portable-deployments, compfuzor-runtime]
status: draft
generated: { by: llm:glm53flashmax (GLM 5.3 Flash Max via OpenCode), at: 2026-09-26 }
verified: { by: none, at: null }
stale_after: 2026-12-26
sources:
  - id: parent-intent
    resource: cotail://ses_f2198ade (quiet-tiger, gpt-6-astra#medium, 2026-09-26)
    title: Parent session holding the confext direction and FS_CONTAINERD archaeology request
  - id: steamos-fs-session
    resource: cotail://ses_f60ab652 (happy-garden, glm-5.3#high, 2026-09-14 → 09-21)
    title: Steam Deck installation and layered-filesystem design — the live FS_CONTAINERED discussion
  - id: iface-session
    resource: cotail://ses_f21dff9f (jolly-moon, glm-5.3#max, 2026-09-26)
    title: DHCP + secondary static IP — the systemd-iface playbook work being done now
  - id: mkosi-session
    resource: cotail://ses_054f118f (stellar-falcon, glm-5.2, 2026-07-28 → 08-03)
    title: mkosi build investigation — formats inventory incl. sysext/confext and host tooling
  - id: beads-origin
    resource: cotail://ses_39b5275f (silent-cabin, glm-5#default, 2026-02-16)
    title: Session that created the compfuzor-systemd-extensions beads ticket
  - id: runtime-anneal
    resource: cotail://ses_f63a45e2 (crisp-tiger, gpt-5.6-sol#high, 2026-09-13 → 09-14)
    title: Config simplification → compfuzor-runtime annealing session
  - id: self-contained-bundle
    resource: cotail://ses_f32adb69 (proud-river, glm-5.3#max, 2026-09-23 → 09-24)
    title: zim2 install failure and the self-contained runtime bundle attempt
  - id: local-systemd
    resource: ~/archive/systemd/systemd (v261-1244-g8f4cd7de43)
    title: Local systemd checkout used for confext/sysext facts (no web fetch needed)
---

# Archaeology: FS_CONTAINERD, self-contained playbooks, and the confext direction

Underlying model: **GLM 5.3 Flash Max** (filename suffix `fx`).

## Stage setting

What is up: compfuzor-runtime just landed (one multicall `.mjs`, catalog, opt-in
flows) and the operator has a long-wanted idea — **systemd sysext and especially
confext** — as a *post-runtime* flow: a new build step (working name
`build-confext`) that consumes a deployment's existing build materials and
renders a systemd extension bundle the host merges at runtime, with the
[`systemd-iface*`](/systemd-iface-extra-addr.etc.pb) playbooks as the first
target. This wave is archaeology only: recover what actually happened around
"FS_CONTAINERD", why a self-contained playbook was recently needed, where the
material/runtime boundaries sit today, and what that implies for the confext
builder. No implementation.

Two framing quotes from the parent session
(`ses_f2198ade`, quiet-tiger, 2026-09-26), which carry the user's intent
verbatim:

> "we just built this compfuzor-runtime thing. i have an idea for a very bold
> weird feature i've long wanted: systemd sysext and especially confext. send
> an FX to research recent changes around FS_CONTAINERD; we needed a self
> contained playbook recently for something and i need the archaeology on
> that."

> "i also specifically feel like the FS_CONTAINERD discussion somewhat ended at
> an impasse. we got the steam deck support we wanted by using more bind mounts
> @steamos-offload.srv.pb, not by making playbooks significantly better at
> having files in one dir-tree."

And the concrete direction:

> "we have systemd-iface* playbooks that i want to make a confext the systemd
> bundle that can layer in. this would be a post-runtime process of some kind,
> a flow of some kind i guess. probably a new build-confext task that takes
> existing build materials if applicable and renders things down into the
> bundle of whatever type for systemd confext."

## 1. The name "FS_CONTAINERD" — what it resolves to

**Finding: no symbol named `FS_CONTAINERD` has ever existed in the repo.**

- `git log --all -S "FS_CONTAINERD"` returns **zero** commits.
- Working tree grep finds nothing; the closest live symbol family is
  `FS_CONTAINERED` (98 pickaxe hits all-time), a boolean that lived in
  [`tasks/compfuzor/fs_hierarchy.tasks`](/tasks/compfuzor/fs_hierarchy.tasks)
  and swapped each hierarchy family's materialized root with its exposure
  root. The old shape is preserved verbatim in
  [`doc/prefix-transcript.md`](/doc/prefix-transcript.md#L1344-L1345):

  ```yaml
  _dir: "{{FS_CONTAINERED|default(False)|ternary(relative, fsh)}}"
  _link: "{{FS_CONTAINERED|default(False)|ternary(fsh, relative)}}"
  ```

  where `relative = DIR/<family>` and `fsh` = the hierarchy root
  (`/etc/opt/<name>`-style). `FS_CONTAINERED=true` = *materialize inside the
  deployment tree, expose at the system root via a reversed link*.

- The operator uses "fs_containerd" and "fs_containered" interchangeably in the
  live session (`ses_f60ab652`, happy-garden, 2026-09-14):

  > "The FS_CONTAINERD used to flop all the links to be the other way around."

  > "what is the fate of fs_containerd after all this?"

  > "on fs_containered, we fixed steam, but we needed a solution for containers,
  > where we do need to keep everything under a single folder, where we reverse
  > the links too, so we can portably move around a thing."

So the archaeology subject is the **contained-layout machinery** and its
recent replacement. Timeline:

| Date | Commit | What |
|---|---|---|
| 2016-02-21 | `83e3a97f` | earliest pickaxe hit — `FS_CONTAINERED` in the fs_hierarchy era |
| 2026-09-14 | `68c39f8d` | **"Replace filesystem inversion with layout profiles"** — removes `FS_CONTAINERED` from fs_hierarchy; adds `vars/containered.yml` + `vars/steamos.yml` as ordinary extra-vars profiles; compiles deferred link plans in `compile_artifacts.tasks` |
| 2026-09-14 | `66939938` | "Mark superseded SteamOS design direction" |
| 2026-09-16 | `e64f465e` | "Propose mount-centric SteamOS installation" ([`design/steamos-install/steamos-install2.gpt56s.md`](/design/steamos-install/steamos-install2.gpt56s.md)) |
| 2026-09-16 | `284df55f` | "Remove superseded SteamOS path overlays" |
| 2026-09-16 | `4650b5e1` | **"Restore contained layout for portable deployments"** — `vars/containered.yml` comes back (after the SteamOS work had dropped it) specifically for the container/portable-tree use case, with `tests/integration/container_profile.test.py` |

Today: [`vars/containered.yml`](/vars/containered.yml) is the entire mechanism —
a plain vars profile that re-points every family at `DIR` and reverses the
structural links (`ETC: DIR/etc`, `ETC_LINK: /etc/opt/<NAME>`, and so on for
eleven families), documented in [`README.md`](/README.md#L89-L101) ("Vars
profiles"):

> "materializes every hierarchy family inside `DIR` and reverses the structural
> links (e.g. `/etc/opt/<name> -> <DIR>/etc`) for deployments that must be one
> portable tree, such as containers"

`fs_hierarchy.tasks` itself no longer knows about containment at all — the
inversion became data, not code. That is the load-bearing outcome of the whole
FS_CONTAINERD arc.

## 2. The impasse, and how it actually resolved

The live discussion (`ses_f60ab652`) opened as a Steam Deck persistence
problem — "files like /etc are going to keep getting wiped out, is the core
dilemma on steam os" — and the operator pushed back hard on the first
treatment: *"i feel like you are layering on yet more bullshit when my ask was
to cut away some FS_CONTAINERED bullshit that has barely gotten used … this is
a chance for net negative lines of code."*

The landing spot (all in
[`steamos-install2.gpt56s.md`](/design/steamos-install/steamos-install2.gpt56s.md),
and implemented in
[`steamos-offload.srv.pb`](/steamos-offload.srv.pb)):

- SteamOS persistence is owned by **bind mounts** of `/usr/local` and
  `/etc/opt` from the durable offload tree (`holo-offload.target`), so the
  ordinary type layout keeps working unchanged and **no path profile is
  needed** (design lines 38–62, "Why this collapses the problem").
- `FS_CONTAINERED` "remains removed" (line 232); the root-pair machinery is not
  resurrected (line 62).
- The generic container profile is retained: "the generic `containered.yml`
  profile remains for single-tree portable deployments such as containers"
  (line ~280).

So "ended at an impasse" is close but slightly unfair to the outcome: the
**SteamOS** leg resolved decisively (bind mounts win; nothing else landed);
what remained genuinely unresolved is the **portable one-tree** capability
itself — it survives only as an install-time vars flip that reverses links,
which the operator has never been fully happy with ("i guess that is required?
bugger."). Confext is precisely a second attempt at that capability, with
systemd as the enforcer instead of link policy.

## 3. "We needed a self-contained playbook recently" — three threads

The parent's sentence compresses three distinct recent "self-contained"
threads. All three matter to confext, and they are easy to conflate:

### 3.1 A self-contained *tree* (portability) — the FS_CONTAINERD legacy

Covered above: [`vars/containered.yml`](/vars/containered.yml), built for
containers where "we need to keep everything under a single folder … so we can
portably move around a thing." This is the thread the operator means when they
say the discussion ended at an impasse.

### 3.2 Self-contained *playbooks* (flat, readable, all-in-one) — the iface work

This week's [`systemd-iface-*`](/systemd-iface-extra-addr.etc.pb) work
(`ses_f21dff9f`, jolly-moon, 2026-09-26; jj `kuwyxznxlwyy` / git `03a41dcf`,
git `f00b2267`, git `6b882765`):

- The request: "we tried setting up a static ip as secondary to dhcp but we
  just get the static … eventually we want a playbook here too."
- Delivered: [`systemd-iface-extra-addr.etc.pb`](/systemd-iface-extra-addr.etc.pb)
  hardened into a fully self-contained playbook — INSTANCE-driven, runtime
  **discovery** of the governing networkd file via `networkctl` (lines
  17–24), guards against unmanaged/no-DHCP interfaces, its own
  [`README`](/systemd-iface-extra-addr.etc.pb#L78-L120) and an idempotent
  `bin/apply.sh`. [`systemd-iface-static-only.etc.pb`](/systemd-iface-static-only.etc.pb)
  replaced the old broken `systemd-iface-static.etc.pb` (which wrote to a
  directory networkd never reads).
- Same week, the same philosophy was enforced on the Deck playbooks:
  `34518b88` (2026-09-22) "umbriel: keep compositor playbooks self-contained"
  removed `vars/umbriel.yaml` and the generic steamos-session abstraction
  because they were "alien to the repository's normal flat, readable playbook
  style" (`ses_f3aa188b`, neon-wolf, is the session where the over-abstraction
  was walked back).

This is the freshest "we needed a self-contained playbook" — and it is also why
these two playbooks are the initial confext target: they are small, already
all-in-one, and their deliverable is pure `/etc/systemd/network` material.

### 3.3 A self-contained *runnable* — the runtime bundle

`ses_f32adb69` (proud-river, 2026-09-23/24): a fresh-user `install-zim.sh`
failure led to "The fix path needs a self-contained runnable" — building a
no-external-dependency bundle (tsdown) of the runtime. The answer that stuck
(from the earlier recap in that session): no build step needed on the target —
`/opt/zim2-main/bin/compfuzor-runtime.mjs` is the **prebuilt checked-in
artifact** (see §4). This thread is the delivery-model precedent for confext:
build-on-the-controller, ship one immutable artifact.

## 4. Material/runtime boundaries today

The compile/apply seam ([`doc/arch.md`](/doc/arch.md#L28-L45), "The most
important seam is between compile and apply") plus the runtime now makes three
environments ([`doc/config/README.md`](/doc/config/README.md), "Mental model"):

| Environment | What lives there | Key artifacts |
|---|---|---|
| Ansible controller | filter plugins compile declarations | `ETC_FILES`, `BINS`, `LINKS`, `SUBSYSTEM`, catalog/flow JSONs |
| Managed deployment tree (`DIR`) | materialized + linked state, one runtime `.mjs` + aliases | `DIR/etc/` (symlinked to `/etc/opt/<NAME>`), `bin/`, `etc/compfuzor-runtime/catalog.json` |
| Host runtime | systemd + runtime processes | merged configs, enabled units, executed flows |

Concretely, for a `.etc.pb` playbook
([`tasks/compfuzor.includes`](/tasks/compfuzor.includes#L165-L221)): the
FILESYSTEM phase materializes `ETC_FILES` into `DIR/etc/` (the `etc.yaml` type
sets `DIR = /etc/opt/<NAME>`, so `ETC = DIR/etc`), then the LINKS lane copies
or symlinks each record out to its system path — for the iface playbooks, a
drop-in under `/etc/systemd/network/<file>.network.d/`
([`systemd-iface-extra-addr.etc.pb`](/systemd-iface-extra-addr.etc.pb#L74-L80)).
The runtime side ([`runtime/compfuzor-runtime.mjs`](/runtime/compfuzor-runtime.mjs),
141 KB, checked in; delivered by
[`library/filter_plugins/runtime_bundles.py`](/library/filter_plugins/runtime_bundles.py#L14-L24)
as one `compfuzor-runtime.mjs` + symlink aliases) gets an attributed catalog
compiled by [`tasks/compfuzor/gen_runtime_catalog.tasks`](/tasks/compfuzor/gen_runtime_catalog.tasks#L1-L35)
from `BINS` + `ETC_FILES` + the link plan; flow *execution* is opt-in
(`RUNTIME_FLOW_EXECUTION`), read-only inspection is the default, and flows are
"catalog-authorized build, install, or status flow[s] … in lexical order"
([`files/flow/runtime.ts`](/files/flow/runtime.ts#L1-L4)).

The build-lane precedent for a "build-confext task": `build-mise`
([`design/build-mise/draft0.gpt6sol.md`](/design/build-mise/draft0.gpt6sol.md))
— a synthesized bin that runs in the bin-run lane, consumes compiled state,
writes build outputs idempotently, and reports notices back through the
end-of-play handler. A confext builder rhymes with this shape almost exactly.

## 5. confext/sysext grounding (local sources, no web)

From the local checkout `~/archive/systemd/systemd` (v261-1244) and this host:

- **What confext extends**: sysext merges extension images over `/usr` and
  `/opt`; files outside those hierarchies "are not merged … in particular,
  files in `/etc/`" (`man/systemd-sysext.xml` L70–74). confext is the
  counterpart: only `/etc` is merged, and "the merged hierarchy will be mounted
  with `nosuid`" (`man/systemd-sysext.xml` L204–205, confext paragraph).
- **Forms accepted** (same man page L96–113): plain **directories**; **naked
  filesystem images** (erofs, squashfs, ext4); **DDIs** (GPT with partition
  table). Search paths: `/etc/extensions/`, `/run/extensions/`,
  `/var/lib/extensions/` (directory-form also honored there; the last is the
  recommended install location). Merge is overlayfs over the host hierarchy,
  activated by `systemd-sysext`/`systemd-confext` (verbs include
  `status/merge/unmerge/refresh`) or their services at boot.
- **Identity**: an extension must ship
  `/usr/lib/extension-release.d/extension-release.<NAME>` matched against the
  host `os-release` (man L165+); masking is an empty directory named like the
  extension in `/etc/extensions/` (L154–155).
- **DDI recipe**: systemd-repart's own definitions
  (`src/repart/definitions/confext.repart.d/10-root.conf`) are
  `Type=root, Format=erofs, CopyFiles=/etc/, Verity=data, VerityMatchKey=root,
  Minimize=best` — i.e. a confext DDI is an erofs root partition whose content
  is `/etc`, verity-hashed, plus optional verity-sig partitions. (Not verified
  in this pass: which partition *type GUID* confext DDIs are supposed to carry
  in this tree; `usr-extended`/`etc-extended` strings do not appear in
  v261-1244 sources. mkosi owns this today — see next bullet.)
- **mkosi already emits both**: formats include `sysext` and `confext`
  (verified in `ses_054f118f`'s mkosi investigation, 2026-07-28; mkosi checkout
  at `~/archive/systemd/mkosi`). That session also inventoried host tooling
  (nspawn, qemu, `systemd-dissect`, `losetup`) — all present.
- **Host readiness**: this host runs systemd **262~rc3-1** with
  `/usr/bin/systemd-sysext` and `/usr/bin/systemd-confext` installed and
  `systemd-confext.service` enabled. `/var/lib/extensions`, `/etc/extensions`,
  `/run/extensions` do **not** exist yet — confext has never been used here.
- **Standing ticket**: beads `compfuzor-systemd-extensions` (open, P2, created
  2026-02-16 from `ses_39b5275f`, silent-cabin): "Add support for generating
  systemd system extension (sysext) and configuration extension (confext)
  layers … Both use raw GPT disk images with specific partition types and can
  be merged at runtime via systemd-sysext/systemd-confext." The idea is two
  years old and pre-dates all of the machinery above; this wave is the first
  grounded movement on it.

## 6. Implications and open questions for a post-runtime build-confext

What a `build-confext` would consume — the "existing build materials if
applicable" — is already well-defined by the compile seam:

- `ETC_FILES` (+ `FILES`/`DIRS`) already materialize into `DIR/etc/` — that
  tree *is* a confext payload for an etc-type deployment, needing only an
  `extension-release.d` file plus erofs/squashfs/GPT packaging.
- The compiled catalog (`gen_runtime_catalog.tasks`) gives attribution and a
  natural place to declare the bundle (name, scope, resources) the way it
  declares flows today.
- The `build-mise` lane pattern gives invocation/bypass/notice conventions for
  a generated `build-confext.sh` bin; mkosi or `mkfs.erofs` + `systemd-repart`
  are candidate emitters, with mkosi being the one already vetted in-session.

The systemd-iface* initial target stresses three real tensions:

1. **Build-time vs apply-time knowledge.** extra-addr *discovers* the governing
   `.network` basename at apply time (`networkctl`). A confext baked at build
   time must instead declare the drop-in path (`NETWORK_FILE=`) — losing the
   discovery the playbook just gained — unless discovery moves into a small
   post-merge activator. Choose deliberately: confext favors *declared*
   targets; that is a philosophy shift, not just a mechanical one.
2. **Mutability of `/etc`.** confext's merged `/etc` is read-only (`nosuid`,
   immutable while active). Today every compfuzor `.etc.pb` playbook, the LINKS
   lane, and `apply.sh` all *write* into `/etc/systemd/network`. Once a confext
   owns those paths, the ordinary playbook and the bundle fight over the same
   files — masking, ordering, and an unmerge path for the Ansible lane need to
   be co-designed. This is the sharpest unresolved conflict.
3. **Where "post-runtime" sits.** The operator said "post-compfuzor-runtime
   flow … a flow of some kind i guess." Two candidate homes: (a) a bin-run-lane
   build bin (`build-confext.sh`, the build-mise pattern) that renders the
   bundle during the play; (b) a catalog-declared flow the runtime executes
   post-install (`RUNTIME_FLOW_EXECUTION`), which is closer to the operator's
   wording but stacks new responsibilities on the least-vetted component.
   Note the parent session's explicit warning that compfuzor-runtime "is quite
   new … may need significant rework or rewrites … volatile" — building the
   first confext generator on the runtime's flow executor couples the newest
   feature to the least proven one.

Also unresolved (carried from §2): whether confext *replaces* the
[`vars/containered.yml`](/vars/containered.yml) portable-tree story for
containers (a confext DDI is literally "one portable tree"), or the two remain
parallel answers to different consumers. The beads ticket covers both sysext
and confext; sysext (for `/opt`-style material) is the natural sibling and the
ticket's other half.

## Architectural checkpoint report

**What exists.** A fully de-inverted filesystem lane (containment is now a
data profile, `vars/containered.yml`, not machinery); two hardened
self-contained iface playbooks whose deliverable is pure networkd `/etc`
material; a checked-in multicall runtime with catalog + opt-in flows; a
build-lane precedent (build-mise) for generated build bins consuming compiled
state; an open, two-ticket-old beads feature for exactly this (sysext+confext);
mkosi locally vetted as a sysext/confext emitter; host systemd 262~rc3 with
both binaries present and zero extension infrastructure used so far.

**What became possible.** Since the FS_CONTAINERD arc, "one portable tree" no
longer requires link inversion at all: an erofs/GPT bundle + systemd-confext
gives the same capability with systemd enforcing immutability and atomic
refresh. Since the iface hardening, compfuzor has a canonical small `/etc`
playbook pair to pilot it with. Since the runtime catalog, a bundle can be
declared and attributed in machine-readable form instead of ad-hoc.

**What became harder / impossible.** Runtime discovery (extra-addr's
`networkctl` governing-file lookup) cannot be baked into a build-time bundle;
apply-time writers (LINKS copy strategy, `apply.sh`) and a read-only merged
`/etc` are in direct conflict; anything the confext owns leaves the ordinary
Ansible lane's reach while it is merged.

**Unresolved tensions.** Build-time declaration vs apply-time discovery (§6.1);
`/etc` ownership between the playbook lane and the merged hierarchy (§6.2);
generator home — build bin vs runtime flow (§6.3); whether confext supersedes
or coexists with the container profile (§6 end); runtime volatility as a
foundation (parent prompt).

**Proposed next slice.** A `draft` wave (design/confext/) for `build-confext`
that: (1) picks the emitter (mkosi `--format confext` vs hand-rolled
`systemd-repart`/erofs) against the `DIR/etc` payload shape; (2) defines the
bundle declaration surface (catalog-contributed metadata: name, version,
extension-release fields, refresh policy); (3) resolves the `/etc` ownership
rule for a pilot — recommend piloting on
[`systemd-iface-static-only.etc.pb`](/systemd-iface-static-only.etc.pb) rather
than extra-addr first, because static-only needs no discovery and has a clean
declared target path, making it the minimal-tension first bundle; (4) keeps
the runtime-flow home as an explicitly deferred option until the runtime
settles. Close `compfuzor-systemd-extensions`'s confext half into this wave
rather than duplicating it.

## Cross-references

- [`vars/containered.yml`](/vars/containered.yml) and
  [`README.md`](/README.md#L89-L101) — the surviving contained-layout profile;
  the direct ancestor this confext idea grows out of.
- [`design/steamos-install/steamos-install2.gpt56s.md`](/design/steamos-install/steamos-install2.gpt56s.md)
  — the mount-centric SteamOS proposal that removed the path-remapping
  pressure and documented `FS_CONTAINERED`'s removal; its "Open decisions"
  section is the impasse's paper trail.
- [`systemd-iface-extra-addr.etc.pb`](/systemd-iface-extra-addr.etc.pb) /
  [`systemd-iface-static-only.etc.pb`](/systemd-iface-static-only.etc.pb) — the
  initial confext targets; their ETC_FILES/LINKS blocks are the payload
  prototype.
- [`design/build-mise/draft0.gpt6sol.md`](/design/build-mise/draft0.gpt6sol.md)
  — the build-bin lane contract a `build-confext` bin should follow.
- [`design/compfuzor-runtime/assess0.glm53fm.md`](/design/compfuzor-runtime/assess0.glm53fm.md)
  — grounded runtime state (multicall artifact, alias dispatch, catalog);
  [`doc/config/README.md`](/doc/config/README.md) — the three-environment
  mental model.
- [`steamos-offload.srv.pb`](/steamos-offload.srv.pb) — the bind-mount
  resolution that beat the inversion; also a worked example that systemd units
  can own persistence where links cannot.
- beads `compfuzor-systemd-extensions` — the open feature ticket this wave
  operationalizes.

## Appendix: cotail recovery notes

Method: `cotail search` over the compfuzor directory (`--since off` for
exhaustive windows), plus read-only extraction of specific sessions'
user/assistant messages for verbatim evidence. Petnames are cotail session
labels.

| Session | Petname / model | Recovered |
|---|---|---|
| `ses_f2198ade` | quiet-tiger · gpt-6-astra#medium | the parent intent verbatim (3 prompts quoted above); a sibling FX + sol-medium wave |
| `ses_f60ab652` | happy-garden · glm-5.3#high | the full FS_CONTAINERED discussion: "net negative lines of code", "fate of fs_containerd", reciprocal-link reversal requirement, bind-mount resolution, /srv safety findings |
| `ses_f21dff9f` | jolly-moon · glm-5.3#max | the iface playbook request and its final report (discovery, guards, static-only replacement, ifconfig trap) |
| `ses_f63a45e2` | crisp-tiger · gpt-5.6-sol#high | the anneal-into-compfuzor-runtime mandate and zx/effect/Rust hesitancy context |
| `ses_f32adb69` | proud-river · glm-5.3#max | self-contained runnable attempt (tsdown); "no build step needed, `/opt/zim2-main/bin/compfuzor-runtime.mjs` is the prebuilt artifact" |
| `ses_054f118f` | stellar-falcon · glm-5.2 | mkosi format inventory (`sysext`/`confext` among them), host tooling inventory, mkosi sources at `~/archive/systemd/mkosi` |
| `ses_39b5275f` | silent-cabin · glm-5#default | the beads ticket creation prompt; ticket text recovered from `.beads`/`bd show` |

Not recoverable / limits: `FS_CONTAINERD` as a literal symbol appears in no
commit and no session message body outside the operator's own shorthand; the
pre-2016 origin of the contained-layout *idea* (as opposed to the
`FS_CONTAINERED` implementation) is unrecoverable from these sources. The
happy-garden session's final recap message was stored with no extractable
assistant text (compaction-era), so its last-state summary could not be
quoted directly; its user-side messages carry the arc completely. Assistant
messages for some older sessions store content in `content[]` parts rather
than `text`, which the first extraction pass missed; corrected mid-investigation.
