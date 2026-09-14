---
type: Design
title: SteamOS installation and persistence architecture
description: Evidence and design options for deploying Compfuzor across SteamOS A/B image updates.
resource: https://github.com/rektide/compfuzor/blob/main/design/steamos-install/steamos-install.gpt6.md
tags: [compfuzor, steamos, steam-deck, filesystem, persistence, ansible]
status: draft
generated: { by: llm:gpt6, at: 2026-09-14 }
stale_after: 2026-12-14
sources:
  - id: deck-inspection
    resource: ssh://deckercaned
    title: Live Steam Deck inspection running SteamOS 3.9.0 build 20260828.100
    last_modified: 2026-09-14
  - id: steamos-keep-policy
    resource: file:///usr/lib/rauc/atomic-update-keep.conf
    title: SteamOS atomic update retention policy inspected on deckercaned
    last_modified: 2026-08-27
  - id: steamos-sync-var
    resource: file:///usr/lib/holo/holo-sync-var
    title: SteamOS A/B var and etc synchronization implementation inspected on deckercaned
    last_modified: 2026-08-27
  - id: artifact-compiler
    resource: https://github.com/rektide/compfuzor/blob/main/library/filter_plugins/artifact_links.py
    title: Compfuzor filesystem artifact and link compiler
---

# SteamOS installation and persistence architecture

## What is up

The new supergoal is to make Compfuzor install and remain usable on a Steam
Deck. SteamOS atomically replaces A/B root images. The existing
[`steamos-offload.srv.pb`](/steamos-offload.srv.pb) tries to survive that model
by bind-mounting trees from `/home/.steamos/offload`, while the filesystem
pipeline has a global `FS_CONTAINERED` inversion that can materialize hierarchy
artifacts under a deployment's `DIR` and expose them at their normal FHS path.

The immediate questions are:

1. Which paths SteamOS already makes durable?
2. Why did the existing `/usr/local` offload stop working after an update?
3. Is global `FS_CONTAINERED` sufficient, or should placement become a
   per-filesystem-family variable contract?
4. Where should a SteamOS-specific variables layer enter precedence?

## Conclusion up front

**Keep the offload idea, but do not make SteamOS one giant
`FS_CONTAINERED=True` profile.** SteamOS needs three concepts kept distinct:

1. **materialization** — where durable bytes are written;
2. **exposure** — where a consumer sees those bytes;
3. **retention/activation** — how the exposure is reconstructed or carried to
   the other A/B slot.

The current compiler already names the first two concepts as
`materialized_root` and `exposure_root`. The main architectural move should be
to make those roots overrideable per hierarchy family, then retain
`FS_CONTAINERED` only as a compatibility shorthand that supplies old defaults.

A `vars/steamos.yaml` platform layer is warranted, loaded before
[`vars/common.yaml`](/vars/common.yaml) so its defaults win while playbook vars
still have highest precedence. It should select only the routes SteamOS needs;
it should not silently redirect every state, cache, log, runtime, and package
path into `/opt`.

## Evidence from the Deck

The live host `deckercaned` was inspected on 2026-09-14. It runs SteamOS 3.9.0,
build `20260828.100`, on systemd 261.

### Storage and update domains

| Domain | Live implementation | Update behavior | Compfuzor implication |
|---|---|---|---|
| `/usr` and root paths | 5 GiB Btrfs A/B root partitions | Replacement image wins | Do not make these the only copy of authored bytes. |
| `/var` | 256 MiB ext4 A/B partitions | SteamOS reformats the other slot, then `rsync`s most state; selected package/kernel state is excluded | Ordinary small mutable state can survive, but `/var` is not a large durable payload store. |
| `/etc` | Overlay: image lower + `/var/lib/overlays/etc/upper` | Only paths selected by the built-in and user retention policies are copied to the other slot | `/etc` is writable but selectively persistent, not generally durable. |
| `/home` | Shared 943 GiB ext4 partition | Shared across A/B | Durable authority. |
| `/opt`, `/srv`, `/nix`, `/root` | Native SteamOS bind mounts from `/home/.steamos/offload/*` | Shared across A/B | `/opt` and `/srv` are already durable; Compfuzor should use rather than recreate these mounts. |
| `/usr/local` | No native offload on this host | Image-owned unless Compfuzor's custom mount is active | Keep one small bootstrap mount if standard `/usr/local/{bin,src,share}` paths are desired. |

SteamOS already supplies `opt.mount` and `srv.mount`, wanted by
`holo-offload.target`. Both bind directly from `/home/.steamos/offload`. This
makes a broad Compfuzor-owned `/opt` offload redundant.

### `/etc` is selective, not simply wiped

`/usr/lib/rauc/atomic-update-keep.conf` says that arbitrary `/etc` changes are
discarded, but includes several classes by default. Relevant built-in entries
include:

```text
/etc/atomic-update.conf.d/*.conf
/etc/systemd/system/*.wants/**
/etc/systemd/system/*.service
/etc/systemd/system/*.service.d/**
/etc/systemd/system/*.socket
/etc/systemd/system/*.socket.d/**
/etc/systemd/system/*.mount
/etc/systemd/system/*.mount.d/**
```

Users may add narrow rules through `/etc/atomic-update.conf.d/*.conf`; those
rule files are themselves retained. SteamOS explicitly warns against retaining
all of `/etc/**`, because old files would indefinitely shadow image updates.

### Reconstruction of the broken offload

The current host has:

```text
/etc/systemd/system/usr-local.mount
  -> /etc/opt/steamos-offload-usr-local/usr-local.mount
```

The first symlink survived the update because SteamOS retains system mount
units. Its target did not survive because `/etc/opt/**` is not in the retention
policy. `systemctl` therefore reports `usr-local.mount` as `bad`/`not-found`,
and `/usr/local` is not mounted.

The previous update backup proves that the target unit existed before the
switch:

```text
/var/lib/steamos-atomupd/etc_backup/2026-09-12_14-51-47.tar.xz
  etc/opt/steamos-offload-usr-local/usr-local.mount
  etc/systemd/system/usr-local.mount
  etc/systemd/system/steamos-offload.target.wants/usr-local.mount
```

This is a two-hop persistence failure, not evidence that custom mount units
cannot survive SteamOS updates.

Current Compfuzor's
[`files/systemd/install-unit.sh`](/files/systemd/install-unit.sh) publishes a
unit from `$DIR/etc/<unit>`. If `etc` is materialized inside a durable `DIR`, the
retained `/etc/systemd/system/*.mount` link can point directly to durable
storage and avoid the missing `/etc/opt` intermediate entirely.

## Current Compfuzor seams

### Variable precedence

[`tasks/compfuzor/vars_base.tasks`](/tasks/compfuzor/vars_base.tasks) currently
loads:

1. `vars/common.user.yaml` when `USERMODE` is requested;
2. `vars/common.yaml`;
3. `vars/types/<type>.yaml`;
4. later private/configset varsets.

The custom `include_defaults` action is first-writer-wins: it includes only keys
that are still undefined. This is a good fit for a platform layer if ordered as:

```text
playbook vars (already defined; always win)
  -> user-mode defaults
  -> detected platform defaults
  -> common defaults
  -> type defaults
  -> private/configset defaults
```

Loading SteamOS after `common.yaml` would make the platform file mostly inert.
Loading it before `common.user.yaml` would incorrectly defeat user-mode path
selection. The platform belongs between those two existing layers.

### Filesystem inversion

[`library/filter_plugins/artifact_links.py`](/library/filter_plugins/artifact_links.py)
currently hard-codes:

```text
FS_CONTAINERED=false:
  materialized_root = hierarchy root
  exposure_root     = DIR/<kind>

FS_CONTAINERED=true:
  materialized_root = DIR/<kind>
  exposure_root     = hierarchy root
```

This is useful and no longer merely an executor trick: the compiled artifact
and deferred-link plans both understand the selected materialized path. The
remaining problem is control granularity. One boolean simultaneously affects
`etc`, `var`, `log`, `spool`, `cache`, `src`, `pid`, and `share`.

On SteamOS those families should not share one durability policy. In
particular, containerizing PID/runtime state into persistent `/opt` or `/srv`
is actively undesirable, while containerizing authored config is valuable.

## Option space

### A. SteamOS sets global `FS_CONTAINERED=True`

This is the smallest tracer bullet and would repair the direct source path for
generated systemd units whenever `DIR` is durable.

It is not a sound platform default:

- runtime, cache, logs, and durable config become coupled;
- every playbook type must first have a durable `DIR`;
- the family matching the deployment's own type can produce degenerate roots
  such as `DIR/opt` while `DIR` itself is also the hierarchy exposure;
- the profile cannot adopt `/usr/local/share` while treating `/etc/opt`
  differently.

**Use only as a diagnostic or explicit per-playbook override.**

### B. Let `FS_CONTAINERED` accept a list or mapping

For example:

```yaml
FS_CONTAINERED: [etc, share]
```

This is a practical compatibility improvement and a reasonable intermediate
commit. It still encodes placement through the negative concept “containered”
and always couples the two roots as an inversion. It cannot directly express a
third materialization root or “no exposure link.”

**Viable intermediate, weak final vocabulary.**

### C. Expose per-family compiled roots as variables

Provisional names:

```yaml
FS_ETC_MATERIALIZED_ROOT: "{{DIR}}/etc"
FS_ETC_EXPOSURE_ROOT: "{{ETC}}"

FS_VAR_MATERIALIZED_ROOT: "{{VAR}}"
FS_VAR_EXPOSURE_ROOT: "{{DIR}}/var"
```

The compiler consumes an explicit root pair for each family. If either is not
defined, it derives the old pair from `FS_CONTAINERED`, preserving existing
behavior during migration.

Scalar per-family variables fit Compfuzor's first-writer-wins defaults better
than one nested mapping: `vars/steamos.yaml` can define only the `etc` pair and
`common.yaml` can fill every other family without requiring a new deep-merge
protocol. Compilation can still immediately assemble the scalars into one
typed `spec_fs` mapping.

This does not require the public interface to remain a pile of scalars forever.
It establishes the semantic seam first; a later explicit layer compiler could
merge named filesystem-policy mappings into the same spec.

**Recommended destination.**

### D. Redirect every global base to `/opt`

A SteamOS profile could set `SRCS_DIR`, `ETCS_DIR`, `VARS_DIR`,
`GLOBAL_BINS_DIR`, and others under `/opt/compfuzor`.

This gives simple durability but weak host integration. Consumers do not search
`/opt` for executables, systemd units, sysusers fragments, data files, or many
configs. It merely moves the problem into PATH, XDG, and activation glue. It
also ignores SteamOS's already-durable `/srv`, `/var/log`, and selected `/var`
semantics.

**Useful as a fully isolated deployment profile, not the default SteamOS
integration.**

## Recommended SteamOS posture

### Durable materialization

- Use native persistent `/opt` for optional software payloads.
- Use native persistent `/srv` for service deployments.
- Restore the small `/usr/local` offload bootstrap if Compfuzor intends to keep
  standard `.src.pb`, global-bin, and local-share conventions.
- Materialize the `etc` family inside each durable deployment `DIR`.
- Leave PID/runtime roots ephemeral.
- Leave ordinary small `/var` state on `/var`; explicitly offload large service
  state rather than changing every playbook globally.
- Prefer `/usr/local/share` over `/usr/share` for Compfuzor-authored global data
  once `/usr/local` is durable.

### Exposure and retention

- Publish systemd units directly from durable `$DIR/etc` into
  `/etc/systemd/system`; SteamOS already retains those unit links and their
  `.wants` links.
- Expose contained standard config with one top-level symlink per deployment:
  `/etc/opt/<name> -> <DIR>/etc`.
- Add a narrow SteamOS retention rule for `/etc/opt/*`, preserving the
  top-level exposure links without copying the contained payload into the A/B
  `/var` partitions.
- Extend retention only for declared integration artifacts outside
  `/etc/opt`, such as selected sysusers, modules-load, sysctl, udev, or desktop
  configuration links. Never default to `/etc/**`.
- Longer term, derive candidate retention entries from compiled `LINKS` whose
  destination is under `/etc`, then require an explicit policy for each rather
  than assuming every `/etc` link should shadow future image content.

### Platform layer

Introduce detected host-platform defaults independently of playbook `TYPE` and
deployment `USERMODE`. A provisional platform contract is:

```yaml
# vars/steamos.yaml — exact names remain a design choice
COMPFUZOR_PLATFORM: steamos
FS_ETC_MATERIALIZED_ROOT: "{{DIR}}/etc"
FS_ETC_EXPOSURE_ROOT: "{{ETC}}"
SHARES_DIR: /usr/local/share
STEAMOS_ATOMIC_KEEP:
  - /etc/opt/*
```

Do not put package installation into this profile. SteamOS package mutations
are image-local and are a separate capability with a separate persistence and
reapplication decision.

## Bootstrap path on a fresh Deck

The inspected image includes `python`, `git`, `podman`, `distrobox`, `curl`,
and `wget`, but not `uv`, `uvx`, or Ansible. Therefore installation does not
need to begin by mutating the SteamOS package image.

A first bootstrap can remain entirely in the shared home partition:

1. clone Compfuzor under the user's home;
2. create a user-owned Python virtual environment or install a standalone `uv`
   under `~/.local`;
3. install a compatible `ansible-core` plus Compfuzor's Python dependencies;
4. run playbooks with `-i 'localhost,' -c local`;
5. use one authenticated `sudo` activation to publish the retained mount and
   integration links.

The existing [`ansible-uvx.opt.pb`](/ansible-uvx.opt.pb) is not itself a fresh
bootstrap because its wrappers require `uvx` to pre-exist. On the inspected
Deck, its `/opt/ansible-uvx-main` payload survived the OS update while `uvx`
did not, leaving durable but unusable wrappers. The eventual installer should
own this prerequisite rather than assume a previous package install.

## Suggested tracer sequence

1. **Prove the repaired `/usr/local` mount:** run `steamos-offload.srv.pb` with
   only the `etc` family materialized under durable `DIR`; verify the installed
   unit link points directly into `/srv/.../etc`, not `/etc/opt/...`.
2. **Add narrow `/etc/opt/*` retention:** generate a Compfuzor-owned
   `/etc/atomic-update.conf.d/` rule and use `holo-sync-var --dry-run` to verify
   the exposure links are retained while contained payload files are not copied.
3. **Add explicit per-family root inputs:** preserve boolean behavior as the
   fallback, then test mixed routes (`etc` contained, `var` split, `pid`
   ephemeral).
4. **Add the platform layer:** auto-detect SteamOS, apply only platform
   defaults, and prove playbook vars and USERMODE still win.
5. **Build the no-host-package bootstrap:** exercise it from a user home with
   Ansible absent from `/usr`.
6. **Reboot and update simulation:** verify units, exposure links, `/usr/local`,
   status scripts, and one representative service. A real A/B update is the
   final proof; a retention dry-run is not equivalent.

## Decisions still needed

1. Should `/usr/local` remain the compatibility bridge, or should SteamOS use
   `/opt` plus user-facing PATH/XDG links and avoid a custom global mount?
2. Should per-family root variables be public stable inputs immediately, or an
   internal compiled seam behind a smaller `FS_LAYOUT_<KIND>` selector first?
3. Should Compfuzor generate one static `/etc/opt/*` retention rule, or compile
   a precise retention manifest from each deployment's exposure plan?
4. Is installing Arch packages an explicit reapply-after-update capability, or
   should the SteamOS goal avoid host package installation entirely?

## Cross-references

- [`/steamos-offload.srv.pb`](/steamos-offload.srv.pb) — the existing bind-mount
  recipe whose generated unit crossed the failed two-hop path.
- [`/overlay.etc.pb`](/overlay.etc.pb) — prior attempt to overlay an image path;
  useful evidence, but its upper under slot-local `/var` and its missing unit
  target share the same update problem.
- [Filesystem pipeline option space](/.design/fs-pipeline/draft0.gpt56.md) —
  establishes `materialized_root` and `exposure_root` as compiled filesystem
  concepts and argues for explicit `spec_fs` before apply.
- [Compiled artifacts and deferred link plans](/.design/link-script/draft2-0.gpt56.md)
  — explains the current inversion and why generated publication should use
  the actual materialized source.
- [Architecture contract](/doc/arch.md#hierarchy-and-fanout-interaction) — keeps
  hierarchy resolution, compiled declarations, and filesystem effects as
  separate responsibilities.
- [Global deploy, user service](/.design/global-usermode/init0.opencode.md) —
  nearby precedent for separating durable global materialization from
  per-context activation and for using `fsh` as a path-composition vocabulary.
