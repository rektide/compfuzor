---
- hosts: all
  vars:
    README: |
      pstore/ramoops — captures kernel oops/panic logs in reserved RAM that survive reboot.

      Requires only the `ramoops` module (CONFIG_PSTORE_RAM).

      PSTORE_CONSOLE, PSTORE_PMSG, and PSTORE_FTRACE are compile-time kernel
      options (not modules). If your kernel was built without them, the
      console_size, pmsg_size, and ftrace_size params are accepted but those
      buffers will never be written to. On such kernels only oops/panic dmesg
      capture works — which is the critical part.

      Check your kernel config:

          grep -E 'PSTORE_RAM|PSTORE_CONSOLE|PSTORE_PMSG|PSTORE_FTRACE' /boot/config-$(uname -r)

      You must also reserve physical memory for ramoops. Add to your kernel
      cmdline: `memmap=256K$0x...` (address of your choosing). The ramoops
      module will claim this region via mem_size.
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
