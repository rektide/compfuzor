---
type: Documentation
title: linux-config-debplus — debplus kernel configuration material
description: Compfuzor deployment-only management of the imported debplus kernel config corpus and its AMDGPU power hotfix script.
resource: /doc/linux-debplus/README.md
tags: [kernel, debian, amdgpu, import]
status: stable
generated: { by: agent:glm-5.3-flash, at: 2026-10-01 }
verified: { by: agent:glm-5.3-flash, at: 2026-10-01 }
stale_after: 2027-01-01
sources:
  - id: material
    resource: /usr/local/src/linux-config-debplus
    title: linux-config-debplus local jj repo (import source)
    author: rektide
    last_modified: 2026-08-09
---

# linux-config-debplus

[`/linux-config-debplus.src.pb`](/linux-config-debplus.src.pb) puts the
debplus kernel configuration corpus under compfuzor declared-FILES
management. It is **deployment-only**: it declares and restores bytes, and
it does not configure, build, install, patch, or boot anything. The Linux
checkout itself (`/usr/local/src/linux`), its build output, and its
jj/git metadata are not owned here.

## Provenance

Imported byte-exact (cmp-verified, 20 files) on 2026-10-01 from the
self-owned local jj repo at `/usr/local/src/linux-config-debplus` into
[`files/linux-config-debplus/`](/files/linux-config-debplus/). The inputs
are Linux 7.1-era: the running debplus kernel was built from commit
`987301279ffaf3a6f2eaca7ad7f4a8b7eec3008e` (parent = the `v7.1` tag,
build timestamp 2026-08-09). The source repo remains the upstream home
for this material; compfuzor manages a faithful mirror of it, not its
history. The historical `archive/` subtree is retained verbatim
(old Kconfig scratch, superseded hotfix scripts/patches/source backups);
nothing in the current workflow reads it.

## Material

| File | Role |
|---|---|
| `config-debian-plus` | Complete ready-to-use kernel configuration |
| `overrides.config` | Deliberate deltas from Debian's config (compiler-agnostic) |
| `overrides.llvm` / `overrides.gcc` | Per-toolchain policy fragments (`LLVM=1` canonical, GCC fallback) |
| `DEBIAN.md` | Configuration, packaging, install, symbols, alternate flows |
| `MAKE.sh` | **Historical saved command** for the 7.1.0-1 package build; not expanded into build automation |
| `hotfixes/amdgpu-power.sh` | Explicit `--check`/apply script for the AMDGPU minimum-power-cap source change |
| `archive/` | Superseded material, retained for context |

## Playbook shape

- Standard `import_tasks: tasks/compfuzor.includes` with `type: src`;
  `NAME: linux-config-debplus` pinned so the default
  `DIR` (`{{SRCS_DIR}}/{{NAME}}`) is exactly the existing
  `/usr/local/src/linux-config-debplus` directory.
- `FILES` rows use `copyDir: true` — an odd name, but it routes the copy
  module's `src` branch, which copies bytes verbatim for single files as
  well as directories. The content path would corrupt bytes: even
  `raw: true` only skips templating, while the underlying `file` lookup
  rstrips trailing newlines.
- Suppressed by design: no `REPO` (existing jj/git metadata never
  managed), `FS_SRCS_BYPASS` (no `/opt` presence link for a repo already
  at its SRCS_DIR home), `BINS_RUN_BYPASS`, no packages, no
  `KERNEL_PARAMS`, no readme synthesis (the imported `README.md` is
  material, not generated furniture).
- `FS_BACKUP: true` — declared FILES that differ in the existing
  directory are backed up next to their destination before overwrite.
- Staging: run with `-e DIR=/some/stage/path` (as the
  [`.test-agent/linux-debplus/`](/.test-agent/linux-debplus/README.md)
  verification runs do) to generate without touching the real directory.
  Standard compfuzor furniture (`env`, `env.export`, `etc` symlink) still
  appears inside DIR, and `/etc/opt/linux-config-debplus` is created.

## Usage

Restore the configuration (from any cwd; Kconfig accounts for source
version drift):

```sh
cp /usr/local/src/linux-config-debplus/config-debian-plus \
  /usr/local/src/linux/.config
make -C /usr/local/src/linux LLVM=1 olddefconfig
```

Build the package: **run `MAKE.sh` from the kernel checkout's cwd**, not
from the config repo — the script exports reproducibility variables and
invokes a bare `make`, so it resolves the tree from the current
directory:

```sh
cd /usr/local/src/linux
sh /usr/local/src/linux-config-debplus/MAKE.sh
```

Check or apply the AMDGPU hotfix (explicit human action; the playbook
never runs it):

```sh
sh /usr/local/src/linux-config-debplus/hotfixes/amdgpu-power.sh \
  --check /usr/local/src/linux
sh /usr/local/src/linux-config-debplus/hotfixes/amdgpu-power.sh \
  /usr/local/src/linux
```

## AMDGPU power override semantics

The hotfix adds the opt-in kernel parameter
`amdgpu.ignore_min_pcap=1` (module param, mode 0600). Semantics: when
set, the reported *minimum* power cap reads as `0` and the set-limit
range check ignores the firmware minimum. The **upper bound is kept** —
`max_power_limit` is still enforced — and the GPU firmware can still
reject out-of-range requests on its own. `--check` passing (or a clean
apply) establishes only that the source hunks fit; it **does not**
establish kernel-version compatibility, nor build or runtime success.

## Current-checkout incompatibility (as checked 2026-10-01)

The live `/usr/local/src/linux` checkout is
`v7.3-rc3-60-g587858367581` (HEAD `587858367581b9c55c3690f4e63382ad622
719d4`, 2026-09-14, 2367 locally dirty files) — two minor lines past the
7.1-era material. The hotfix `--check` fails concretely:

```
error: patch failed: drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c:149
error: drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c: patch does not apply
error: patch failed: drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c:2987
error: drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c: patch does not apply
```

Structural cause: the upstream SWSMU power-limit API the patch targets
is gone — `min_power_limit` fields/functions are absent;
`smu_get_ppt_limit` (~line 2940) and `smu_set_ppt_limit` (~3015) now work
through `ppt_limits.range[power_source][limit_type]` with
`od_min`/`min` and `od_max`/`max`, and no `ignore_min_pcap` text exists
in any of the four target files. The patch is preserved exactly as
imported; porting it to the new API is a separate, deliberate follow-up.
The captured transcript lives in
[`.test-agent/linux-debplus/README.md`](/.test-agent/linux-debplus/README.md).

## Cross-references

- [`design/blueturn/kernel-uhid-shortreport.general.md`](/design/blueturn/kernel-uhid-shortreport.general.md)
  — prior research that ties the running `7.1.0-debplus.1` kernel to
  commit `9873012` (parent `v7.1`) and identifies `hotfixes/amdgpu-power.sh`
  as the re-apply vehicle (lines ~114-127); its upgrade discussion
  (~line 418) already advises treating a 7.3 re-apply as an "upgrade,
  not a fix" — the concrete failure above confirms that read.
- [`/pstore.etc.pb`](/pstore.etc.pb) — policy consumer of the persistent
  crash evidence this corpus retains: `overrides.config` keeps the exact
  `CONFIG_PSTORE*` block (`PSTORE`, `COMPRESS`, `RAM`, `CONSOLE`,
  `FTRACE`, `PMSG`) that playbook documents at runtime.
- [`/crashkernel.etc.pb`](/crashkernel.etc.pb) — the capture-kernel side
  of the same crash-diagnostic design: the corpus keeps
  `CONFIG_DEBUG_INFO`/BTF and pstore policy that kdump workflows rely on.
