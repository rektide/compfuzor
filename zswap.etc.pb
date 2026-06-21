---
- hosts: all
  vars:
    KERNEL_MODULES:
      zswap:
        params:
          enabled: Y
          compressor: lz4
          zpool: zsmalloc
          max_pool_percent: "14"
          accept_threshold_percent: "90"
          same_filled_pages_enabled: Y
          exclusive_loads: Y
          shrinker_enabled: Y
    # debugfs zswap stats, surfaced by the generic status-dirs.sh reporter
    # (root-only, hence _SUDO). zswap params come from status-modules.ts via
    # KERNEL_MODULES above. The status subsystem generates status.sh, which
    # runs both reporters.
    STATUS_DIRS_SUDO:
      - /sys/kernel/debug/zswap
  tasks:
    - import_tasks: tasks/compfuzor.includes
