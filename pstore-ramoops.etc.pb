---
- hosts: all
  vars:
    KERNEL_MODULES:
      ramoops:
        params:
          mem_size: 0x40000
          record_size: 0x4000
          console_size: 0x20000
          ftrace_size: 0x10000
          pmsg_size: 0x10000
          ecc: 0
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

          PARAMS_DIR="/sys/module/ramoops/parameters"
          PSTORE_DIR="/sys/fs/pstore"

          if [ -d "$PARAMS_DIR" ]; then
            show_dir "$PARAMS_DIR" "ramoops parameters"
          else
            echo "=== ramoops module not loaded ==="
          fi
          echo

          if [ -d "$PSTORE_DIR" ] && [ "$(ls -A "$PSTORE_DIR" 2>/dev/null)" ]; then
            echo "=== pstore records ==="
            for f in "$PSTORE_DIR"/*; do
              [ -f "$f" ] || continue
              echo "--- $(basename "$f") ---"
              cat "$f"
              echo
            done
          else
            echo "=== no pstore records ==="
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
