---
type: ArchitectureCheckpoint
title: Systemd unit copy and link representations under LINKS ownership
description: Implement stable runtime copy/link publication and composition exclusion for systemd units without treating systemd scope as a CONFIG context.
resource: /design/install-context/systemd-links0.solx.md
tags: [compfuzor, systemd, links, copy, symlink, composition, scope]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-13 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-13 }
stale_after: 2026-10-13
sources:
  - id: systemd-context-comparison
    resource: /design/install-context/systemd0.unknown.md
    title: Systemd scope bindings are not CONFIG contexts
  - id: links-runtime
    resource: /files/links/links.ts
    title: LINKS runtime manager
  - id: systemd-installer
    resource: /files/systemd/install-unit.sh
    title: Shared systemd unit installer
---

# Systemd unit copy and link representations under LINKS ownership

## Checkpoint

The bounded delivery mismatch identified in
[`systemd0.unknown.md`](/design/install-context/systemd0.unknown.md#7-privilege-and-links-interactions)
is resolved without systemd command consolidation or CONFIG context reuse.
Systemd still has generated, hard-scoped unit leaves and manager operations;
LINKS now has enough vocabulary to own either physical representation of the
published unit.

Two former complete-install failures are closed:

1. a unit copied by `--copy`, `SYSTEMD_COPY`, or `SYSTEMD_INSTALL_COPY` remains
   a healthy declared copy after the later LINKS records lane;
2. systemd link bypass remains authoritative because unit publication records
   are visible to LINKS ownership commands but excluded from generic plan
   composition.

## Durable schema and compatibility

The LINKS manifest remains version 1. Two additive optional record fields are
normalized by [`compile_links`](/library/filter_plugins/artifact_links.py):

```json
{
  "strategies": {"available": ["link", "copy"], "default": "link"},
  "compose": false
}
```

Keeping version 1 is deliberate: old readers already consume record mappings,
and the new runtime gives absent fields the old semantics—link-only,
default-link, composed. Ordinary records are not widened implicitly. Compiled
output emits the fields only when declared, while systemd declares both
strategies and composition exclusion explicitly.

`compose` is named for plan composition rather than installation or ownership.
`false` does not make a record observational, dormant, or unmanaged. It only
omits it from `links.ts apply --composed`, the fixed command used by generated
`install-link-records[-user].sh`. Direct full apply, direct apply by ID,
status, audit, and remove still include it. This keeps sequencing explicit:
systemd publishes before daemon reload; the generic lane does not infer phases.

## One shared representation decision

The runtime classifies each destination once and shares that assessment across
status, apply, and remove:

| Entry | Declared healthy condition | Result |
|---|---|---|
| Symlink | Managed normalized target path and `link` available | Healthy `representation: link` |
| Regular file | Source available, bytes equal, and `copy` available | Healthy `representation: copy` |
| Missing | None | Missing; apply uses selected strategy or record default |
| Foreign/dangling symlink or modified/undeclared copy | None | Existing record policy governs |
| Directory or special | Never replaceable | Visible and preserved |

A healthy nondefault representation is clean. Unqualified apply preserves it.
`--strategy copy|link` is an explicit switch and has no fallback when selected
records do not offer it. Systemd's `policy: replace` therefore supports both
intentional switching and recovery from modified regular files or foreign
symlinks. There is no force switch, receipt, or automatic pruning.

Removal remains conservative. A byte-equal declared copy can be removed while
its source is available. A modified copy or a copy whose source has vanished
cannot be proven managed and is preserved. Existing normalized-target link
removal remains possible even when the source is gone.

Atomic copy gained the same injectable executor seam as atomic link. System
records retain LINKS `auto`/`always`/`never` routing for both forms; user records
never sudo and reject `always` before mutation. CONFIG continues importing the
same delivery primitives with unchanged behavior.

## Systemd leaf behavior

[`install-unit.sh`](/files/systemd/install-unit.sh) delegates both managed forms
to `links.ts apply --id UNIT_LINK_ID` when the manager is installed. Selection
is:

```text
explicit --copy / --link
  > SYSTEMD_INSTALL_COPY / SYSTEMD_COPY environment
  > compiled LINKS record default
```

With no runtime override, the helper deliberately omits `--strategy`: LINKS
can preserve a healthy nondefault representation. The compiled default is
bound both in the record and as `UNIT_LINK_DEFAULT` for manager-absent fallback.
`SYSTEMD_INSTALL_STRATEGY` is the canonical playbook setting; existing
generation-time copy booleans map to `copy`, while the default remains `link`.

Fallback direct delivery remains supported and now uses `SUDO_CMD` for parent
creation as well as copy/link mutation. Publication bypass skips the entire
delivery step and manager reload as before. Daemon reload, typed enable targets,
enable/start policy, and hard system/user manager bindings did not change.

The compiler also rejects a user-scope install whose unit type maps to a
non-user manager directory, such as network or nspawn. This closes the exposed
`/etc` plus user-manager/no-sudo contradiction rather than teaching LINKS a new
scope or path selector.

## Why this is not context unification

Representation is a strategy of one declared source/destination ownership
relationship. CONFIG context is a named consumer binding that selects roots,
recipes, and defaults. Systemd scope still selects manager, authority, and in
some modes distinct rendered bytes. Sharing atomic delivery and copy/link
health does not align those selectors or their status domains.

No selected context, CONFIG path selector, universal operation plan, systemd
command registry, live `systemctl`, live sudo, package operation, or prune path
was added.

## Verification

Focused coverage proves:

- v1 link-only behavior and additive strategy/compose validation;
- matching link and byte-equal copy health with reported representation;
- default creation, healthy nondefault preservation, explicit switching, and
  unavailable-strategy preflight failure;
- foreign/modified/dangling policy behavior and directory/special refusal;
- conservative removal of matching versus modified/unverifiable copies;
- system/user copy and link sudo routing through shims only;
- composed defaults, composition exclusion, status visibility, and direct-ID
  application;
- a rendered systemd aggregate across default link, explicit/ambient copy,
  later records composition, no-override preservation, explicit switch back,
  and systemd publication bypass;
- fallback privileged parent creation through a sudo shim;
- compile-time rejection of a user-scope network directory map;
- shared CONFIG delivery integration and strict native TypeScript regression.

## Remaining local issues

These stay separate because they are not required by representation delivery:

1. `SYSTEMD_ROOTS` separate-mode source rendering can still disagree with the
   generated `-user` install binding.
2. Systemd still lacks a domain status for manager load freshness, enablement,
   and explicitly modeled activation expectations. LINKS status covers only
   publication representation.
3. Mixed-scope drop-in composition remains a separate systemd design question.

## Cross-references

- [`systemd0.unknown.md`](/design/install-context/systemd0.unknown.md) supplies
  the accepted boundary: retain generated systemd bindings and fix the local
  LINKS interactions without adopting CONFIG context selection.
- [`doc/subsys.md`](/doc/subsys.md#declared-links-and-shared-link-delivery) is
  the maintained schema, operator behavior, privilege, and systemd publication
  reference.
- [`command0-review0.solx.md`](/design/config-context/command0-review0.solx.md)
  is relevant counterpoint: CONFIG has fixed actions over selected consumer
  contexts, while this work adds only representation and composition policy to
  declared LINKS ownership.
- [`doc/bins.md`](/doc/bins.md) explains why hard system/user systemd leaves and
  subsystem compositors remain unchanged.
- [`systemd_links.test.py`](/tests/integration/systemd_links.test.py) is the
  rendered complete-install evidence; [`test_runtime_manager.py`](/tests/links/test_runtime_manager.py)
  covers the representation lifecycle independently.
