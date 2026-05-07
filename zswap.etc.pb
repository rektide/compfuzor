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
          shrinker_enabled: Y
    BINS:
      - name: status.sh
        basedir: False
        content: |
          show_dir() {
            local dir="$1" title="$2"
            echo "=== $title ==="
            for f in "$dir"/*; do
              echo "$(basename "$f"): $(cat "$f")"
            done
          }

          PARAMS_DIR="/sys/module/zswap/parameters"
          DEBUG_DIR="/sys/kernel/debug/zswap"

          show_dir "$PARAMS_DIR" "zswap parameters"
          echo

          if [ -d "$DEBUG_DIR" ]; then
            show_dir "$DEBUG_DIR" "zswap stats"
          else
            echo "debugfs zswap stats not available (mount debugfs?)"
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
