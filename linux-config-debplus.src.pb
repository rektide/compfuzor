---
# Deployment-only management for the debplus kernel configuration material.
# Imported 2026-10-01 from the self-owned local jj repo at
# /usr/local/src/linux-config-debplus (Linux 7.1-era inputs); see
# doc/linux-debplus/README.md for provenance, usage, and known limits.
#
# This playbook declares and restores bytes. It does not configure, build,
# install, patch, or boot anything. The Linux checkout at
# /usr/local/src/linux, its build output, and its jj/git metadata are NOT
# owned here: no REPO, no KERNEL_PARAMS, no bins, no packages, and no
# readme synthesis. hotfixes/amdgpu-power.sh stays an explicit
# --check/apply script run by a human; MAKE.sh is retained as a historical
# saved command, not expanded into build automation.
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
    - name: config-debian-plus
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
      mode: "0644"
    - name: hotfixes/amdgpu-power.sh
      copyDir: True
      mode: "0755"
    # Historical archive, retained verbatim; nothing in the current
    # workflow reads it.
    - name: archive/previous-normalization/.config
      copyDir: True
      mode: "0644"
    - name: archive/previous-normalization/.config.old
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
