---
type: ArchitectureCheckpointReview
title: Systemd LINKS delivery review corrections
description: Correct manifest versioning, empty composition tiers, dangling source topology, and legacy systemd copy override parsing.
resource: /design/install-context/systemd-links0-review0.solx.md
tags: [compfuzor, systemd, links, manifest, symlink, composition, environment]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-13 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-13 }
stale_after: 2026-10-13
sources:
  - id: reviewed-checkpoint
    resource: /design/install-context/systemd-links0.solx.md
    title: Systemd unit copy and link representations under LINKS ownership
  - id: systemd-context-boundary
    resource: /design/install-context/systemd0.unknown.md
    title: Systemd scope bindings are not CONFIG contexts
---

# Systemd LINKS delivery review corrections

## Outcome

Independent review found four release blockers in the bounded systemd/LINKS
delivery implementation. All four are corrected without changing systemd's
command topology, designing manager status, broadening CONFIG context, or
performing live operations.

## 1. Representation semantics require manifest version 2

[`compile_links`](/library/filter_plugins/artifact_links.py) now emits version 2
for every current durable LINKS plan. [`links.ts`](/files/links/links.ts) accepts
both versions with an explicit boundary:

| Manifest | Record semantics |
|---|---|
| v1 | Strict historical link-only, default-link, composed behavior. `strategies` or `compose` is a clear rerender/version error. |
| v2 | Optional `strategies` and `compose`, with absent fields retaining link-only/default-link/composed defaults. |
| other | Unsupported-version error. |

This prevents a v1 label from activating behavior unknown to the v1 contract.
Existing old v1 manifests continue through their complete lifecycle. Current
compiled plans use v2 consistently even when every record happens to be
link-only.

Zim's [`withRegistryManifest`](/files/zim/install.ts) and legacy host
[`zim-registry.sh`](/files/zim-registry.sh) manifests remain intentionally v1.
Both are temporary, contain one ordinary link-only record, and use neither v2
field; migrating them would communicate no additional behavior. The focused
Zim consumer lifecycle exercises these strict-v1 paths successfully.

## 2. Composition no longer emits an empty install tier

Runtime ownership assets and plan composition are now separated during
generation as well as application. A scope receives
`install-link-records[-user].sh` only when at least one record in that scope has
`compose` absent or true. Therefore a systemd-only plan still emits:

- `links.json` v2;
- the LINKS runtime modules;
- status and audit access;
- explicit remove and direct apply commands;

but it emits no `install-link-records.sh`, no `install-links.sh` compositor, and
no LINKS child in `install.sh`. A mixed plan emits generic installation only in
participating scopes. This is generation filtering, not pruning: stale scripts
from older deployments remain deliberate cleanup work.

## 3. Link topology and copy usability use different source facts

The first implementation followed the source with `stat` for both strategies,
which regressed historical LINKS topology: a source path that is itself a
dangling symlink was misreported as absent and could not be linked.

The shared destination assessment now tracks:

1. source directory-entry existence using `lstat`, for link strategy;
2. a regular-file referent using `stat`, for copy strategy.

Consequences:

- old v1 link-only records can create a destination link to a dangling source
  symlink and report an exact destination link as managed;
- a truly absent source path remains `SOURCE_MISSING`;
- copy requires a source resolving to a regular file;
- copy-selected dangling symlinks and non-file sources return
  `SOURCE_UNUSABLE`, exit 2, perform no replacement, and never fall back to
  link;
- an unqualified operation still preserves an already healthy declared link,
  even if copy is also available or is the record default.

CONFIG's delivery and status model is unchanged. The correction is inside the
LINKS ownership classifier; shared atomic primitives retain their existing
interfaces and behavior.

## 4. Legacy systemd copy variables are defined-value booleans

[`install-unit.sh`](/files/systemd/install-unit.sh) now resolves runtime
selection in this order:

```text
explicit --copy / --link
  > SYSTEMD_INSTALL_COPY, when defined
  > SYSTEMD_COPY, when defined
  > no runtime override
```

Values are case-insensitive. `true`, `yes`, `y`, `1`, and `on` select copy.
`false`, `no`, `n`, `0`, `off`, and empty mean no override. A false value does
not select link: the manager call omits `--strategy`, preserving a healthy
representation or using the compiled default when missing. Because precedence
is based on definition, `SYSTEMD_INSTALL_COPY=false` masks
`SYSTEMD_COPY=true`, matching Ansible's defined-value precedence. Invalid
spellings fail with exit 2 before publication or manager reload.

The same resolution feeds manager-backed and direct fallback delivery.
Explicit strategy remains highest and does not consult lower legacy values.

## Verification

Focused tests cover:

- current v2 compilation, v1 lifecycle compatibility, rejection of v2 fields
  under v1, and unsupported versions;
- v2 copy/compose behavior and strategy validation;
- v1 dangling-source link creation/status, true source absence, explicit copy
  rejection, default-copy `SOURCE_UNUSABLE`, and no fallback or replacement;
- all-systemd composition with no generic LINKS install files or top child;
- mixed-scope generation with an installer only for the composed scope;
- manager-backed and fallback truthy/falsy parsing, YAML-style capitalization,
  preferred-name masking, explicit precedence, invalid-value exit 2, and no
  publication/reload on error;
- artifact compiler, LINKS runtime/status/delivery, existing systemd behavior,
  CONFIG toolkit regression, shell syntax, and strict native TypeScript.

No live `systemctl`, sudo, package installation, push, prune, or broad test
sweep was performed.

## Remaining local issues

The review does not change the next independent concerns:

1. `SYSTEMD_ROOTS` separate-mode source rendering mismatch;
2. systemd manager/reload/enablement status design;
3. mixed-scope drop-in composition.

## Cross-references

- [`systemd-links0.solx.md`](/design/install-context/systemd-links0.solx.md) is
  the reviewed implementation checkpoint; this review supersedes its manifest
  version and generated-install-tier claims.
- [`doc/subsys.md`](/doc/subsys.md#declared-links-and-shared-link-delivery) is
  the maintained operator and schema reference after correction.
- [`systemd0.unknown.md`](/design/install-context/systemd0.unknown.md) remains
  the architectural boundary: shared filesystem delivery does not turn systemd
  manager scope into a CONFIG context.
