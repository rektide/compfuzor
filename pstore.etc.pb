---
- hosts: all
  vars:
    README: |
      # pstore/ramoops

      > Captures kernel oops/panic logs in reserved RAM that survive reboot.

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
    # /sys/fs/pstore records, surfaced by the generic status-dirs.sh reporter
    # (file contents; multi-line record dumps are newline-escaped in TSV and
    # preserved in JSON). ramoops params come from status-modules.ts via
    # KERNEL_MODULES above. The status subsystem generates status.sh, which
    # runs both reporters.
    STATUS_DIRS:
      - /sys/fs/pstore
  tasks:
    - import_tasks: tasks/compfuzor.includes
