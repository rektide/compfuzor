---
- hosts: all
  vars:
    TYPE: zswap
    INSTANCE: main

    KERNEL_MODULES:
      zswap:
        params:
          enabled: Y
          compressor: lz4
          zpool: z3fold
          max_pool_percent: "20"
          accept_threshold_percent: "90"
          same_filled_pages_enabled: Y
          exclusive_loads: Y

  tasks:
    - import_tasks: tasks/compfuzor.includes
