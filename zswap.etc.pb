---
- hosts: all
  vars:
    KERNEL_MODULES:
      zswap:
        params:
          enabled: Y
          compressor: lz4
          zpool: zsmalloc
          max_pool_percent: "20"
          accept_threshold_percent: "90"
          same_filled_pages_enabled: Y
          exclusive_loads: Y
  tasks:
    - import_tasks: tasks/compfuzor.includes
