---
# Deployment-only management for the debplus kernel configuration material.
# Initially imported 2026-10-01 from the local jj repo at
# /usr/local/src/linux-config-debplus; the bundle README now carries the
# maintained 7.3 target, provenance, usage, and verification limits.
#
# This playbook declares and restores bytes. It does not configure, build,
# install, patch, or boot anything. The Linux checkout at
# /usr/local/src/linux, its build output, and its jj/git metadata are NOT
# owned here: no REPO, no KERNEL_PARAMS, no bins, no packages, and no
# readme synthesis. hotfixes/amdgpu-power.sh stays an explicit
# --check/apply script run by a human; MAKE.sh remains an explicit package
# build recipe, not an automatically executed deployment step.
#
# FILES rows use copyDir:true — an odd name, but it routes the copy
# module's src branch (which works for individual files as well as
# directories) and writes bytes verbatim. The content path would lose
# trailing newlines: even raw:true only skips templating, while the
# underlying file lookup rstrips.
- hosts: all
  gather_facts: False
  vars:
    TYPE: linux-config-debplus
    # Pinned so the src-type default DIR ({{SRCS_DIR}}/{{NAME}}) is exactly
    # the existing /usr/local/src/linux-config-debplus directory. Override
    # DIR with -e DIR=... to stage elsewhere (as .test-agent runs do).
    NAME: linux-config-debplus
    # Back up declared FILES that differ in the existing directory.
    FS_BACKUP: True
    # The material is already at its SRCS_DIR home inside its own jj repo;
    # no /opt presence link, and nothing here runs generated bins.
    FS_SRCS_BYPASS: True
    BINS_RUN_BYPASS: True
    FILES:
    - name: README.md
      copyDir: True
      mode: "0644"
    - name: DEBIAN.md
      copyDir: True
      mode: "0644"
    - name: config-debian-plus.xz
      copyDir: True
      mode: "0644"
    - name: overrides.config
      copyDir: True
      mode: "0644"
    - name: overrides.llvm
      copyDir: True
      mode: "0644"
    - name: overrides.gcc
      copyDir: True
      mode: "0644"
    - name: MAKE.sh
      copyDir: True
      mode: "0755"
    - name: hotfixes/amdgpu-power.sh
      copyDir: True
      mode: "0755"
    - name: tests/amdgpu-power/README.md
      copyDir: True
      mode: "0644"
    - name: tests/amdgpu-power/run.py
      copyDir: True
      mode: "0755"
    - name: tests/amdgpu-power/stubs.h
      copyDir: True
      mode: "0644"
    - name: tests/amdgpu-power/assertions.c
      copyDir: True
      mode: "0644"
    - name: tests/package-recipe/make-sh-guards.sh
      copyDir: True
      mode: "0755"
    # Maintenance tools promoted from the gitignored 2026-10-01 verification
    # session: standalone config diff, bundle verification, fixture runner.
    # TypeScript ports (run directly with node, no build step); the replaced
    # Python tools were deleted in the same change.
    - name: tools/diff-configs.ts
      copyDir: True
      mode: "0755"
    - name: tests/bundle/verify.ts
      copyDir: True
      mode: "0755"
    - name: tests/tools/run.ts
      copyDir: True
      mode: "0755"
    - name: baselines/7.1/README.md
      copyDir: True
      mode: "0644"
    - name: baselines/7.1/config-running.xz
      copyDir: True
      mode: "0644"
    - name: baselines/7.1/config-upstream-defconfig.xz
      copyDir: True
      mode: "0644"
    - name: baselines/7.1/config-running-vs-defconfig.diff
      copyDir: True
      mode: "0644"
    - name: baselines/7.1/config-running-vs-defconfig.fragment
      copyDir: True
      mode: "0644"
    - name: baselines/7.1/config-running-normalization.diff
      copyDir: True
      mode: "0644"
    - name: baselines/7.1/source-config-inventory.json
      copyDir: True
      mode: "0644"
    - name: baselines/7.1/validation.json
      copyDir: True
      mode: "0644"
    - name: baselines/7.3/README.md
      copyDir: True
      mode: "0644"
    - name: baselines/7.3/config-upstream-defconfig.xz
      copyDir: True
      mode: "0644"
    - name: baselines/7.3/config-debian-plus-vs-defconfig.diff
      copyDir: True
      mode: "0644"
    - name: baselines/7.3/defconfig-to-debian-plus.fragment
      copyDir: True
      mode: "0644"
    # Authenticated Debian retrieval and independently reviewed config layers.
    # Declare files explicitly rather than copying Python bytecode/cache dirs.
    - name: debian/README.md
      copyDir: True
      mode: "0644"
    - name: debian/retrieve.ts
      copyDir: True
      mode: "0755"
    - name: debian/test-retrieve.ts
      copyDir: True
      mode: "0755"
    - name: debian/required-intent.config
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/experimental/receipt.json
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/experimental/InRelease.xz
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/experimental/Sources.xz
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/experimental/source-index-receipt.json
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/receipt.json
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/InRelease.xz
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/config-7.2.8-1-amd64.xz
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/audit.json
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/policy-declared-vs-debian.diff
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/target-debian-vs-upstream.diff
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/target-policy-vs-debian.diff
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/target-policy-unfulfilled.diff
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/target-required-intent-unfulfilled.diff
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/target-toolchain-metadata.diff
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/target-upstream.config.xz
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/target-debian.config.xz
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-7.3/target-policy.config.xz
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-running-7.1/audit.json
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-running-7.1/policy-declared-vs-debian.diff
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-running-7.1/our-current-vs-debian.raw.diff
      copyDir: True
      mode: "0644"
    - name: debian/snapshots/unstable/audit-running-7.1/our-current-declared-policy-vs-debian.diff
      copyDir: True
      mode: "0644"
    # Historical archive, retained verbatim; nothing in the current
    # workflow reads it.
    - name: archive/previous-normalization/config-debian-plus.7.1.0.xz
      copyDir: True
      mode: "0644"
    - name: archive/recovered-inputs/README.md
      copyDir: True
      mode: "0644"
    - name: archive/recovered-inputs/config-6.13-amd64.xz
      copyDir: True
      mode: "0644"
    - name: archive/recovered-inputs/config-7.1.3+deb14.xz
      copyDir: True
      mode: "0644"
    - name: archive/recovered-inputs/mise.toml.recovered
      copyDir: True
      mode: "0644"
    - name: archive/previous-normalization/.config.xz
      copyDir: True
      mode: "0644"
    - name: archive/previous-normalization/.config.old.xz
      copyDir: True
      mode: "0644"
    - name: archive/previous-normalization/Makefile
      copyDir: True
      mode: "0644"
    - name: archive/amdgpu-power/AMD-HOTFIX.backup-20260808-153751.sh
      copyDir: True
      mode: "0644"
    - name: archive/amdgpu-power/AMD-HOTFIX.in-tree-original.sh
      copyDir: True
      mode: "0644"
    - name: archive/amdgpu-power/amdgpu-ignore-min-pcap.in-tree-original.patch
      copyDir: True
      mode: "0644"
    - name: archive/amdgpu-power/amdgpu-ignore-min-pcap.original.patch
      copyDir: True
      mode: "0644"
    - name: archive/amdgpu-power/apply-artifacts/amdgpu-ignore-min-pcap.patch-orig
      copyDir: True
      mode: "0644"
    - name: archive/amdgpu-power/apply-artifacts/amdgpu-ignore-min-pcap.url
      copyDir: True
      mode: "0644"
    - name: archive/amdgpu-power/apply-artifacts/source-backups/amdgpu.h.orig
      copyDir: True
      mode: "0644"
    - name: archive/amdgpu-power/apply-artifacts/source-backups/amdgpu_drv.c.orig
      copyDir: True
      mode: "0644"
    - name: archive/amdgpu-power/apply-artifacts/source-backups/amdgpu_pm.c.orig
      copyDir: True
      mode: "0644"
  tasks:
  - import_tasks: tasks/compfuzor.includes
    vars:
      type: src
