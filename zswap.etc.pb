---
- hosts: all
  vars:
    KERNEL_MODULES:
      zswap:
        # Only the five params the kernel still exposes (7.1). The rest were
        # removed upstream:
        #   zpool                     v6.18 5c3f8be0c6b1 deleted the zpool
        #     indirection; zsmalloc is the only allocator, hardcoded.
        #   exclusive_loads           v6.9 c2e2ba770200 made exclusive loads
        #     the only supported mode.
        #   same_filled_pages_enabled v6.10 c074e1467f85 dropped the params;
        #     v6.12 0ca0c24e3211 + 20a5532ffa53 moved zero pages to a swap
        #     bitmap and removed same-filled handling entirely.
        # All predate 7.1, so declaring them made the generated status
        # reporter flag DRIFT (<missing>) on every run; dropping them
        # restores clean status runs.
        params:
          enabled: Y
          compressor: lz4
          max_pool_percent: "14"
          accept_threshold_percent: "90"
          shrinker_enabled: Y
    # debugfs zswap stats, surfaced by the generic status-dirs.sh reporter
    # (root-only, hence _SUDO). zswap params come from status-modules.ts via
    # KERNEL_MODULES above. The status subsystem generates status.sh, which
    # runs both reporters.
    STATUS_DIRS_SUDO:
      - /sys/kernel/debug/zswap
  tasks:
    - import_tasks: tasks/compfuzor.includes
