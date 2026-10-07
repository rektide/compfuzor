---
type: LearningReport
title: Kinefolk background for Surface Dial precision layers
description: Scoped study of kinefolk-rs contexts, F13-F24 mappings, external-remapper posture, and where a physical-modifier-derived precision bit does and does not fit; registers the host-signal idea there.
resource: /design/surface-dial-layers/kinefolk0.glm53.md
status: draft
generated: { by: model:glm-5.3, at: 2026-10-06 }
sources:
  - resource: /design/surface-dial-layers/brief0.gpt61s.md
    title: Inquiry brief directing this study
  - resource: file:///home/rektide/src/kinefolk-rs/README.md
    title: kinefolk-rs workspace overview and boundaries
  - resource: file:///home/rektide/src/kinefolk-rs/context/core/README.md
    title: Named sparse contexts and store contract
  - resource: file:///home/rektide/src/kinefolk-rs/context/example/README.md
    title: Bundled registry and the f() F13-F20 boundary
  - resource: file:///home/rektide/src/kinefolk-rs/cli/kinefolk/README.md
    title: CLI knowledge/access scopes and no-remapper stance
  - resource: file:///home/rektide/src/kinefolk-rs/core/model/README.md
    title: Native model values and CoTriggers
  - resource: file:///home/rektide/src/kinefolk-rs/kinesis/model/src/kb975/capabilities.rs
    title: Co-trigger assessment and static precedence metadata
  - resource: /kinata.srv.pb
    title: Declared Kinesis-scoped Kanata instance with kinefolk on-board half
---

# Scope and method

Requested shorthand `~/src/kinefolk` does not exist; the checkout studied is
`~/src/kinefolk-rs` (clean jj state at start). Learning was read-only: READMEs,
design indexes, and the context/model/catalog code paths below. No kinefolk
code was written, no hardware/profile operation performed, and no service,
grab, or injection occurred. Kinefolk is treated as background and idea
registration only — **not a deployment dependency** of the dial work. Other
current-wave documents in this directory were deliberately not read.

# What kinefolk-rs is

A Rust workspace for the Kinesis Freestyle Edge RGB (KB975, `29ea:0103`):
tree-sitter SmartSet grammar, an owned native value model, a KB975
catalog/token layer, source-preserving decode/encode/diff/apply, device status
probing, verified capture plus deliberate selected-profile layout writes, and
host-side named-context authoring (`context`, `core/*`, `kinesis/*`, `cli`).
The root [README](file:///home/rektide/src/kinefolk-rs/README.md) frames it as
inspection, authoring, and deliberate apply — never a resident process.

# Findings by scoped question

## Named contexts and layers

`Context { name, description, layout, notes }` holds a complete **sparse**
`LayoutIntent` — a final map, not a delta and not a stack. Contexts are
independent standalone definitions: "Contexts are independent definitions, not
an implicit stack"; `jk`/`left-right`/`page`/`mid-nav`/`f` are alternative
assignments, not layers of one system. "Layer" in kinefolk means the native
SmartSet per-key layer dimension (`top`, `fn` as catalog `LayerId`s addressing
`KeyAddress`), which is a *configuration address*, not kanata-style runtime
layer switching. Persistence is copy-on-edit TOML
(`$XDG_CONFIG_HOME/finefolk/context/<name>.toml`); local shadows override
bundles, nothing is pruned or reconciled automatically.

## Native mappings, including F13–F24

`KeyCode::F13..=F24` all exist as output values
([`core/model/src/output.rs:53–64`](file:///home/rektide/src/kinefolk-rs/core/model/src/output.rs)),
and the TOML codec round-trips spellings `f13`..`f24`
([`codec.rs:152–153`](file:///home/rektide/src/kinefolk-rs/context/store/src/codec.rs)).
KB975 has no physical F21+ positions — these are output meanings any physical
key can be authored to emit. Allocation status today:

| Codes | Status |
|---|---|
| F13–F20 | Bundled `f` context: hk1–hk8 → F13–F20, "confirmed portion only" |
| F21–F22 | Earmarked by [`kinata.srv.pb`](/kinata.srv.pb) on-board half (`[hk5]>[f21]`, `[hk6]>[f22]`, then kanata maps f21→lalt/f22→lmet) — declared, not evidenced as applied |
| F23–F24 | Unallocated and unaccepted — competing candidates: keyboard-held mode signal (registered idea) vs dial direction events ([routing](/design/surface-dial-layers/routing0.gpt61s.md)) |

The registry is explicit that it "invents" no F21–F24 assignment
([`context/example/src/lib.rs:38–49`](file:///home/rektide/src/kinefolk-rs/context/example/src/lib.rs)).

## External remapper and protocol hooks: none today

- CLI: "there is no automatic migration or Kanata/keyd configuration work";
  examples: "No Kanata or keyd configuration is introduced."
- Accepted design language: `core/encode` is "an intentionally SmartSet-specific
  codec seam, not a general protocol plugin trait"
  (`design/core-model-operations/model1-operations.gpt6am.md`).
- Division of labor is deliberate, not integration: "The user expects Kanata may
  handle most daily remapping; that did not replace the native utility's scope"
  (`design/completion/completion0.gpt6a.md`).

So kinefolk neither feeds nor consumes any external remapper, and exposes no
export/protocol surface. Any future hook is greenfield surface area.

## Configuration contexts versus runtime modal state

Kinefolk's entire vocabulary is static, authored configuration. It cannot
observe runtime modal state: "configured startup settings do not identify the
live runtime profile"; layout commands "inspect configured source, not the
keyboard's runtime active profile"; `status` cannot determine the live active
profile; firmware refresh after apply is explicitly not confirmed. Macro/remap
precedence exists only as static capability metadata, "not playback
simulation". There is no daemon, no event loop, no host-input knowledge, and no
facility that could hold or publish a live mode bit.

## Where a physical-modifier-derived precision bit fits — and does not

**Fits (keyboard side, configuration only):**

1. *Distinct signal keys.* Kinefolk can author a physical key to emit an
   unallocated code (F23/F24) as an external-consumer mode/precision signal.
   A dedicated keycode is an orthogonal **vocabulary convention**: it avoids
   the modifier-is-a-bit-not-a-count limit and never contends with the Shift
   coordinate (no same-code release collision, per the
   [Kanata assessment](/design/surface-dial-input/kanata-assessment0.gpt61s.md)).
   It is not intrinsic device provenance — any producer can emit the same
   code, and a merged stream still loses original device identity (see the
   [routing assessment](/design/surface-dial-layers/routing0.gpt61s.md)).
   The same F23/F24 tail is also a competing candidate for **dial direction
   events** there; no allocation is accepted, and the two roles require
   coordination.
2. *Keyboard-local modifier conditioning exists but is narrow.* Macro
   co-triggers are physical modifier positions on this keyboard
   ([`capabilities.rs:86–130`](file:///home/rektide/src/kinefolk-rs/kinesis/model/src/kb975/capabilities.rs)):
   a single co-trigger is documented; multiple simultaneous are assessed
   `Unproven` ("app-model evidence only"); a trigger cannot be its own
   co-trigger; LeftGui co-triggers carry a discouraged-use advisory. This is
   the only native physical-modifier facility, and it emits from the keyboard.

**Does not fit:**

1. *A live precision bit.* The requested tier is derived from **physical
   keyboard Shift held while the dial ticks**. The keyboard cannot observe the
   dial, the compositor, or host state, and kinefolk has no runtime to observe
   or publish anything. Sourcing "is physical Shift held?" is a daemon-side
   (or compositor/IPC-side) responsibility, outside kinefolk entirely.
2. *Continuous held-Shift state publication.* Conditioning a **separate
   trigger** on Shift is source-permitted — macro co-triggers do exactly that
   without consuming Shift — and is distinct from continuous held-state
   publication. What is absent: the current Kinefolk API provides no
   transparent global Shift-down/up side-effect hook, and no firmware
   construction has been demonstrated that preserves typing Shift while
   continuously publishing its held state.
3. *Deployment dependency.* None of the dial path may require kinefolk; the
   daemon could equally use its own distinct-key chord or an IPC state with no
   kinefolk involvement.

# Registration

kinefolk-rs has no idea tracker (no beads, no ideas/proposals directories;
design topics are self-indexed). Per its conventions, registration is a design
document in an appropriate domain grouping plus a minimal index cross-link:

- Idea: [`design/host-signal/idea0.glm53.md`](file:///home/rektide/src/kinefolk-rs/design/host-signal/idea0.glm53.md)
- Index: [`design/host-signal/index.md`](file:///home/rektide/src/kinefolk-rs/design/host-signal/index.md)
- Commit: `kkmlvqtq` / git `b335b9541ff4` — "Register host-signal idea for
  external precision consumers" (only those two files).

The registered scope: (a) authoring dedicated key codes as host-consumed
signal **vocabulary** (F23/F24 named as unaccepted candidates that also
compete with the dial direction-event role in the
[routing assessment](/design/surface-dial-layers/routing0.gpt61s.md);
F13–F20 and F21/F22 allocations respected); (b) a future reserved-purpose
metadata channel so diffs/imports surface consumer dependencies instead of
silently repurposing a signal key; (c) a possible future external-remapper
export seam — explicitly noted as nonexistent today. Registration records
direction only; no implementation is requested.

# Current capabilities vs registered future proposals

| Capability | Status |
|---|---|
| Author a key to emit F13–F24 and apply it deliberately | Available now via contexts/`profile apply` |
| Bundled F13–F20 mapping (`f` context) | Available, confirmed-portion only |
| Reserved-signal metadata (semantic or advisory) | Registered idea, not designed |
| Export/protocol seam to external remappers | Registered idea; today none exists |
| Runtime observation of host modifier state | Out of scope by architecture; not registered as a goal |
| Live precision bit feeding the dial | Not a kinefolk concern; daemon-side question |

# Unresolved tensions

- **Interaction mismatch.** The user wants a *Shift-held-derived* extra-fine
  tier; kinefolk can only offer a *dedicated key* or keyboard-local
  co-trigger conditioning. The Shift-derived path must be solved by the dial
  daemon observing physical Shift through its own means; kinefolk's
  contribution is at most reserved vocabulary (e.g. an F24 chord
  discriminator) — one encoding option, not a requirement, matching the
  brief's open question.
- **Allocation lives in prose.** F21/F22 are earmarked only in playbook
  comments and F23/F24 nowhere machine-readable; the registered metadata idea
  exists precisely because nothing today would catch a future context
  repurposing a reserved code. F23/F24 additionally compete between the
  keyboard mode-signal role registered in kinefolk-rs and the dial
  direction-event role in the routing assessment — neither accepted.
- **Unverified daemon key bitmap.** Whether the dial daemon's virtual keyboard
  advertises F13–F24 is not established by the sources read here (the Kanata
  assessment lists only a partial capability set). Any distinct-key chord
  encoding must verify the daemon can actually emit the chosen code.
- **Advisory vs semantic reservation.** Whether a reserved-signal declaration
  should influence diff/replace behavior or remain metadata is left open in
  the registration.

# Next slice

Parent synthesis across the wave should weigh tier encodings: daemon-side
distinct-key chord (needs the key-bitmap verification above), compositor/IPC
state transport, or a kinefolk-authored signal key as a different interaction.
If a reserved code is chosen, record its allocation against the registered
host-signal idea rather than in another playbook comment.

# Cross-references

- [Inquiry brief](/design/surface-dial-layers/brief0.gpt61s.md): direction and
  boundaries this study operated under.
- [Routing assessment](/design/surface-dial-layers/routing0.gpt61s.md): F23/F24
  dial direction-event candidacy and the device-provenance limits that bound
  this study's signal-vocabulary claims.
- [Input assessment](/design/surface-dial-input/assessment0.gpt61s.md): the
  modifier-is-a-bit limit and cross-keyboard mask aggregation this study's
  vocabulary argument builds on.
- [Kanata assessment](/design/surface-dial-input/kanata-assessment0.gpt61s.md):
  same-coordinate release collision motivating an orthogonal signal vocabulary.
- [`kinata.srv.pb`](/kinata.srv.pb): declared F21/F22 earmark and the
  kinefolk-on-board division of labor.
- [Registered idea in kinefolk-rs](file:///home/rektide/src/kinefolk-rs/design/host-signal/idea0.glm53.md):
  the registration artifact referenced above.

# Addendum: precision corrections from parent review

Two claims were narrowed after reading the [routing
assessment](/design/surface-dial-layers/routing0.gpt61s.md); the original
stage is preserved in the prior commit and the inline text above reflects both
corrections. First, a reserved F23/F24 tail is an orthogonal **vocabulary
convention**, not intrinsic device provenance: any producer can emit the code,
and merged streams still lose original device identity — provenance is a
publisher-side designation. F23/F24 also compete between this study's
keyboard mode-signal framing and the routing assessment's dial direction
events; no allocation is accepted, and the roles need coordination. Second,
Shift-conditioned emission was overstated: macro co-triggers permit a separate
trigger conditioned on Shift without consuming it, distinct from continuous
held-state publication. The accurate limit is the absence of a transparent
global Shift-down/up side-effect hook and of any demonstrated firmware
construction that preserves typing Shift while continuously publishing its
held state.
