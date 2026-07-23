---
- hosts: all
  vars:
    README: |
      # pstore/ramoops

      > Captures kernel oops/panic logs in reserved RAM that survives reboot.

      ## Three pieces, all required

      Ramoops silently fails if any one of these is missing. The original
      version of this playbook only did piece #2 and never captured anything.

      1. **Reserved physical RAM** via `memmap=` on the kernel cmdline. The
         region is excluded from normal kernel allocation and survives reboot.
         Without this, ramoops has nothing stable to write to across reset.
         Expressed here as a raw kernel token via `KERNEL_PARAMS` (compfuzor's
         mechanism for cmdline tokens that don't fit `<module>.<param>=<value>`
         shape); `install-kernel-params.sh` writes them to `/etc/kernel/cmdline`.

      2. **ramoops module params** (`mem_address`, `mem_size`, …) pointing at
         that reservation. On a modular kernel, ramoops loads from initramfs
         before `/etc/modprobe.d/` is parsed, so these MUST reach it via the
         kernel cmdline. The `force_cmdline: True` flag on each entry tells
         `install-kernel.sh` to use the cmdline path (not modprobe.d)
         regardless of built-in detection.

      3. **`pstore.backend=ramoops`** plus **blacklist efi_pstore**. pstore
         permits exactly one backend; `efi_pstore` autoprobes very early via
         systemd's module autoload and wins the slot. `pstore.backend=` pins
         the choice on the cmdline; the modprobe blacklist stops efi_pstore
         from even loading — belt and suspenders.

      ## Address selection (RAMOOPS_MEM_ADDRESS)

      Default `0x100000000` (start of the 4 GB boundary) works on any x86_64
      host with ≥ 8 GB RAM: above the BIOS MMIO holes (which all live under
      4 GB), inside the first chunk of upper RAM, and stable across kernels.
      Override per-host for unusual e820 layouts or smaller boxes.

      Verify the address is in usable RAM:

          sudo awk '/System RAM/{print}' /proc/iomem

      ## Apply and verify

      After running this playbook, run `sudo "$DIR/bin/install.sh"`. Then on
      the next boot:

          cat /proc/cmdline                          # memmap=, ramoops.*, pstore.backend=
          ls /sys/module/ramoops/parameters/         # populated
          journalctl -k | grep pstore                # 'Registered ramoops' (no 'already in use')
          ls /sys/fs/pstore/                         # empty until a crash

      ## Why this exists at all

      `efi_pstore` writes crash records to EFI variables. It works for *clean*
      panics but is unreliable for hard resets, OOM-kill cascades, or any fault
      where the firmware doesn't get a clean write window to EFI vars — exactly
      the cases you most want captured. Ramoops writes to reserved RAM that the
      firmware doesn't touch on reset, so it survives those scenarios.

      `PSTORE_CONSOLE`, `PSTORE_PMSG`, and `PSTORE_FTRACE` are compile-time
      kernel options (not modules). If your kernel was built without them, the
      `console_size`, `pmsg_size`, and `ftrace_size` params below are accepted
      but those buffers will never be written to. Oops/panic dmesg capture
      (the critical part) works regardless.

          grep -E 'PSTORE_RAM|PSTORE_CONSOLE|PSTORE_PMSG|PSTORE_FTRACE' /boot/config-$(uname -r)

    # Physical address reserved for ramoops. Default works on any x86_64 with
    # ≥ 8 GB RAM (4 GB boundary, above BIOS MMIO holes). Override per-host
    # via -e RAMOOPS_MEM_ADDRESS=0x... for unusual layouts.
    RAMOOPS_MEM_ADDRESS: "0x100000000"
    RAMOOPS_MEM_SIZE: "0x40000"  # 256 KB

    # Raw kernel cmdline tokens that don't fit the <module>.<param> shape.
    # install-kernel-params.sh writes these to /etc/kernel/cmdline
    # idempotently (replace by key prefix, append if absent).
    KERNEL_PARAMS:
      - "memmap={{RAMOOPS_MEM_SIZE}}${{RAMOOPS_MEM_ADDRESS}}"

    # force_cmdline: True on each entry forces install-kernel.sh to emit
    # these on /etc/kernel/cmdline (as <module>.<param>=<value> tokens) even
    # though ramoops and pstore are modular — modprobe.d is too late for
    # them, since ramoops loads from initramfs and pstore.backend is read
    # at kernel init.
    KERNEL_MODULES:
      ramoops:
        force_cmdline: True
        params:
          mem_address: "{{RAMOOPS_MEM_ADDRESS}}"
          mem_size: "{{RAMOOPS_MEM_SIZE}}"
          record_size: 0x4000
          console_size: 0x20000
          ftrace_size: 0x10000
          pmsg_size: 0x10000
          ecc: 0
      pstore:
        force_cmdline: True
        params:
          backend: ramoops

    # Ensure ramoops is loaded at boot. It's modular on most kernels and the
    # pstore backend slot only gets taken when the module actually registers.
    MODULES:
      - ramoops

    # Blacklist efi_pstore so it cannot grab pstore's only backend slot
    # before ramoops probes. pstore.backend=ramoops above is the primary
    # mechanism; this is belt-and-suspenders against future module-load
    # ordering surprises. compfuzor has no first-class blacklist primitive,
    # so we drop a raw fragment into /etc/modprobe.d/ via ETC_FILES + LINKS
    # (same pattern kernel-pcie-aspm.etc.pb uses for `options` lines).
    ETC_FILES:
      - name: blacklist-efi-pstore.conf
        content: |
          # pstore.etc.pb: efi_pstore autoprobes before ramoops can register
          # and grabs pstore's only backend slot. Disable it so ramoops wins.
          # pstore.backend=ramoops on the kernel cmdline is the primary pin;
          # this is the secondary defense.
          blacklist efi_pstore
    LINKS:
      - src: "{{ETC}}/blacklist-efi-pstore.conf"
        dest: "/etc/modprobe.d/blacklist-efi-pstore.conf"

    # Applying is done via the auto-generated compositor:
    #   sudo "$DIR/bin/install.sh"
    # which runs install-kernel.sh (module params via force_cmdline),
    # install-kernel-cmdline.sh (<module>.<param>=<value> tokens), and
    # install-kernel-params.sh (the raw memmap= token from KERNEL_PARAMS).
    # No SYSTEMD service: pstore only writes /etc/kernel/cmdline; a reboot or
    # `sudo kernel-install` propagates it to BLS entries.

    # /sys/fs/pstore records, surfaced by the generic status-dirs.sh reporter.
    # Should be empty in steady state; non-empty after a crash.
    STATUS_DIRS:
      - /sys/fs/pstore
  tasks:
    - import_tasks: tasks/compfuzor.includes
