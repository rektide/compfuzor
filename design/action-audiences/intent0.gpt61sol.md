---
type: DesignBrief
title: Action audiences without separate playbooks
description: User-directed inquiry into audience-selecting action aliases, user-first defaults, and CONFIG stage reuse as a successor to USERMODE.
resource: /design/action-audiences/intent0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-06 }
verified: { by: unverified }
sources:
  - resource: /design/keybindings/adoption0.glm53.md
    title: Previous topology checkpoint whose audience interpretation the operator corrected
  - resource: /library/filter_plugins/bin_composers.py
    title: Existing action and scope composition to investigate
  - resource: /vars/common.user.yaml
    title: Existing USERMODE overrides to preserve during the inquiry
---

# Situation

The Surface Dial investigation led to adoption of the keybinding consumer
hosts and a media-key producer. The operator then corrected the interpretation
of the earlier decision to retire `.user.pb`: **one playbook per deployment
does not mean system-first behavior or system-only deployment material**.
The intended audience remains primarily users, with system installation also
available. The preceding conversation's claim that `/etc/opt` should remain
the preferred topology is not accepted as a consequence of that filename
decision.

This inquiry is broader than keybindings. It concerns generated action entry
points throughout Compfuzor and how CONFIG stages can share that interface.
The already-implemented SteamOS binding conversion is prior work, not evidence
that its new installer shape settles this broader design.

# Operator direction

- Retain the existing `USERMODE` mechanism for now. Design the new mechanism
  as its eventual replacement, not merely another spelling for its hard switch.
- Keep explicit user and system operations available from one playbook and
  preferably one action implementation.
- Make the unqualified action user-first under the new mode. Do not limit
  audience selection to `install`; other actions should follow the same rule.
- Prefer one real action file with symlink aliases. The latest proposed shape:
  a real `install-user.sh` with `install.sh` and `install-system.sh` aliases
  when user is default; the converse when system is default.
- The real filename conveys the default audience; an explicitly invoked alias
  can select the other audience. This is a design preference to investigate,
  not yet a verified behavior of the generator or runtime.
- Support omitting user/system installation or installation entirely. The
  precise availability policy still needs clarification.
- Avoid bespoke domain commands as the ordinary operator interface:
  `keybindings.mjs` is not the desired endpoint. Explore general action
  commands, potentially `assemble.mts` with audience aliases.
- Investigate the Zim2/Mise2 CONFIG rework before inventing an assembly stage.
  Assembly may be a step within CONFIG rather than a separate parallel system.

# Distinctions to preserve

| Concern | Question |
|---|---|
| Default audience | What does an unqualified action select? |
| Available audiences | Which explicit user/system operations exist? |
| Action availability | Can install be absent while configuration/assembly remains available? |
| Invocation identity | Which spelling was invoked before resolving symlinks? |
| Implementation identity | Which physical executable and deployment supply the operation? |
| Material placement | Where are rendered declarations, profiles and executables stored? |
| Receiver placement | Which user or system roots receive assembled material and links? |
| CONFIG stages | Which operations already own registration, assembly, validation and publication? |

An audience alias alone does not relocate existing deployment material. The
design must account explicitly for the operator's home-local placement intent,
rather than claiming user-scoped effects settle that question. Conversely,
moving material into a home directory must not erase system operation support.

# Research questions

1. What prior work already implements invocation-based variants or shared
   implementations? Which parts can be reused without adding a dispatcher per
   subsystem?
2. Where did the Zim2/Mise2 stage split land? Which stage assembles data,
   installs receiver links, validates candidates and publishes changes?
3. Can generated action aliases supply audience and context to that machinery
   while preserving native validation and its existing transaction semantics?
4. How can default audience, audience availability and material placement be
   declared independently without creating a large configuration interface?
5. What `.mts` execution and packaging support exists? How should invoked-name
   selection coexist with physical-path resolution and main-module detection?

# Cross-references

- [Keybinding producer guide](/doc/config/keybinding-producers.md): existing
  scoped installers and deployment/profile selectors; reuse these contracts
  rather than bypassing them with audience aliases.
- [Keybinding consumer guide](/doc/config/keybinding-consumers.md): receiver
  assembly and validation contracts that a general action interface must keep.
- [Adoption checkpoint](/design/keybindings/adoption0.glm53.md): historical
  topology and migration evidence. Its system-placement rationale is now under
  operator-directed review; the successful migrations remain useful evidence.
- [SteamOS deployment](/steamos-niri.opt.pb): a concrete mixed-audience case:
  system package/session provisioning and user configuration are different
  operations, not interchangeable copies of one command body.
