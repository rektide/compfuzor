---
- hosts: all
  vars:
    TOOL_VERSIONS:
      nodejs: True

    README: |
      # pstore/ramoops

      > Retains compact crash evidence in reserved RAM across a warm reset.

      Ramoops complements, but does not replace, kdump. Ramoops is small and
      resilient enough to retain text from failures where a crash kernel cannot
      start. Kdump can preserve the failed kernel's complete memory image when
      its more complex transition succeeds. See `kernel-panic-main/README.md`
      for panic conversion and `crashkernel-main/README.md` for kdump policy.

      Ordinary DRAM does not survive actual power removal. Ramoops helps with
      kernel-triggered reboot, hardware watchdog reset, firmware warm reset, and
      some reset-button paths. It cannot promise evidence after unplugging power.

      ## Kernel requirements

      The intended kernel has these options:

          CONFIG_PSTORE=y
          CONFIG_PSTORE_COMPRESS=y
          CONFIG_PSTORE_RAM=y
          CONFIG_PSTORE_CONSOLE=y
          CONFIG_PSTORE_FTRACE=y
          CONFIG_PSTORE_PMSG=y

      `PSTORE_RAM=y` registers ramoops during kernel initialization instead of
      waiting for an initramfs module. The other three options are compile-time
      frontends. Ramoops accepts their region sizes even when they are disabled,
      but the unwired regions never receive data.

      ## Evidence allocation

      The 16 MiB reservation is intentionally weighted toward automatic kernel
      evidence rather than divided evenly:

      | Evidence | Allocation | Retention | Value |
      |---|---:|---|---|
      | dmesg | 12 MiB | three physical zones, about 4 MiB each | panic/oops snapshots; highest-value automatic evidence |
      | console | 2 MiB | one continuously overwritten ring | messages already printed before a hang, reset, or early kdump transition |
      | ftrace | 1 MiB | dormant until `record_ftrace` is enabled | last function calls during a targeted hang investigation |
      | pmsg | 1 MiB | userspace-written circular breadcrumbs | useful only when a deliberate `/dev/pmsg0` producer exists |

      Ramoops subtracts the console, ftrace, and pmsg allocations from
      `mem_size`; the remainder becomes dmesg zones. `status-ramoops.sh` checks
      this arithmetic because a backend can register with zero dmesg zones.

      ## Record size and kmsg bytes

      `ramoops.record_size` sets the physical dmesg zone. Pstore fills one
      backend-sized part before checking `pstore.kmsg_bytes`; compression can
      make that part represent more uncompressed printk text than the physical
      zone. Ramoops accepts only part 1, so a conventional multi-megabyte
      `kmsg_bytes` budget can make pstore attempt a second part that ramoops
      rejects during panic.

      `pstore.kmsg_bytes=1` is therefore an intentional one-part sentinel, not a
      one-byte capture limit. The first iteration still fills the effective
      4 MiB zone. Deflate can encode roughly 5.9 MiB of ordinary printk text in
      that zone; incompressible output retains about 3.5 MiB after headers and
      ECC. The sentinel stops before an unsupported second ramoops part.
      `log_buf_len=8M` ensures the source printk ring is itself large enough;
      pstore cannot retain history that printk has already overwritten.

      More zones retain more separate oopses from the current boot. Larger zones
      retain more context for each one. Three zones cover a common sequence of
      an initial oops, a follow-on failure, and a final panic without reducing
      each artifact to a few lines.

      ## Parameter reference

      `memmap=0x1000000$0x100000000` reserves 16 MiB beginning at the 4 GiB
      boundary before the normal page allocator starts. Risk: a fixed address
      must remain ordinary System RAM and must not overlap firmware or device
      mappings. This address was verified against this host's original BIOS E820
      map. It is not a portable default: re-check the pre-`memmap` `BIOS-e820`
      lines in the kernel journal after hardware or firmware changes because
      `/proc/iomem` shows the already-modified map. `status-ramoops.sh` performs
      this post-boot firmware-map check and reports drift if the range is unsafe.

      `ramoops.mem_address=0x100000000` identifies the same physical start to
      ramoops. It must exactly match the address in `memmap=`.

      `ramoops.mem_size=0x1000000` gives ramoops the complete 16 MiB reservation.
      It must exactly match the size in `memmap=`. The cost is permanently
      removing 16 MiB from the system's 64 GiB of allocatable memory.

      `ramoops.record_size=0x400000` targets 4 MiB dmesg zones. Ramoops rounds
      non-power-of-two values down; power-of-two values avoid surprising layout.

      `ramoops.console_size=0x200000` continuously retains the final 2 MiB of
      kernel console output. This is the most useful ramoops stream when a hang
      or successful kdump prevents the final panic-time dmesg callback.

      `ramoops.ftrace_size=0x100000` reserves 1 MiB so persistent tracing can be
      enabled without another reboot. Recording remains off until explicitly
      enabled through debugfs. Persistent function tracing perturbs every traced
      call, so it is an investigation mode rather than a permanent default.

      `ramoops.pmsg_size=0x100000` reserves 1 MiB for `/dev/pmsg0`. Pmsg does not
      automatically copy the journal or application logs: it stores only what a
      userspace writer deliberately sends. Writers must be rate-limited and must
      not persist credentials or document contents into this cross-reboot ring.

      `ramoops.max_reason=2` captures both panics and oopses. Panic-only mode can
      miss the first corruption report that later caused the fatal crash.

      `ramoops.ecc=16` selects 16-byte Reed-Solomon ECC. The kernel also accepts
      `1` as shorthand for 16, but using the effective value keeps sysfs drift
      checks stable. ECC reduces usable bytes in each zone but can repair limited
      corruption after a watchdog reset. It cannot recover powered-off DRAM.

      `ramoops.mem_type=0` uses the default write-combined mapping. The cached
      and noncached alternatives have platform-specific atomicity constraints;
      there is no measured reason to take that risk here.

      `pstore.backend=ramoops` pins the one permitted pstore backend. The
      `efi_pstore` blacklist is a second defense against EFI claiming that slot
      first. EFI variables remain useful elsewhere, but their small size and
      firmware write path are less dependable for this machine's crash problem.

      `pstore.kmsg_bytes=1` forces pstore to stop after the first fully populated
      backend part. This counterintuitive value works because pstore tests the
      budget between parts, not before filling part 1. It avoids a guaranteed
      rejected part 2 while preserving the maximum evidence that one ramoops
      zone can hold.

      `log_buf_len=8M` expands the live printk ring. The cost is 8 MiB of normal
      kernel memory, not persistent RAM. This gives pstore and kdump a longer
      chronology before a noisy driver floods the ring.

      ## Apply and verify

      After running this playbook, run `sudo "$DIR/bin/install.sh"`. The next
      boot should show the 16 MiB reservation and a clean ramoops registration:

          cat /proc/cmdline
          journalctl -k | grep -E 'pstore|ramoops'
          sudo "$DIR/bin/status-ramoops.sh"
          grep -E 'PSTORE_RAM|PSTORE_CONSOLE|PSTORE_PMSG|PSTORE_FTRACE' /boot/config-$(uname -r)

      `systemd-pstore` normally archives records under
      `/var/lib/systemd/pstore` and removes the live copies early in boot. An
      empty `/sys/fs/pstore` therefore does not prove capture failed:

          journalctl -b -u systemd-pstore --no-pager
          sudo "$DIR/bin/pstore-dump.sh"

      For a controlled end-to-end test, first verify `kernel.panic` is nonzero,
      sync filesystems, and use SysRq-c in a maintenance window. LKDTM provides
      more destructive and pathological test cases; it is documented by the
      kernel-panic playbook and is not needed for the first smoke test.

    # pstore ships no systemd service -- opt out explicitly (SYSTEMD_BYPASS
    # alone only skips the thunk, not unit generation).
    SYSTEMD_INSTALL_BYPASS: True
    SYSTEMD_THUNK_BYPASS: True

    # Pstore-specific commands belong to this playbook's generated bin dir,
    # not to the generic kernel/BLS subsystem used by unrelated playbooks.
    BINS:
      - name: status-ramoops.sh
        src: status-ramoops.sh
        basedir: false
      - name: pstore-dump.sh
        src: pstore-dump.sh
        basedir: false

    # Physical address reserved for ramoops. Default works on this x86_64 host
    # (4 GB boundary, above BIOS MMIO holes). Override per-host
    # via -e RAMOOPS_MEM_ADDRESS=0x... for unusual layouts.
    RAMOOPS_MEM_ADDRESS: "0x100000000"
    # 16 MiB total: 12 MiB dmesg + 2 MiB console + 1 MiB ftrace + 1 MiB pmsg.
    # Three 4 MiB dmesg zones retain deep context for up to three incidents.
    RAMOOPS_MEM_SIZE: "0x1000000"

    # Raw kernel cmdline tokens that don't fit the <module>.<param> shape.
    # install-kernel-params.sh writes these to /etc/kernel/cmdline
    # idempotently (replace by key prefix, append if absent).
    KERNEL_PARAMS:
      - "memmap={{RAMOOPS_MEM_SIZE}}${{RAMOOPS_MEM_ADDRESS}}"
      - "log_buf_len=8M"

    # force_cmdline: True on each entry forces install-kernel-modprobe.sh to emit
    # these on /etc/kernel/cmdline (as <module>.<param>=<value> tokens). This is
    # required for the intended built-in ramoops and remains correct on modular
    # distro kernels whose initramfs can load ramoops before root modprobe.d.
    KERNEL_MODULES:
      ramoops:
        force_cmdline: True
        params:
          mem_address: "{{RAMOOPS_MEM_ADDRESS}}"
          mem_size: "{{RAMOOPS_MEM_SIZE}}"
          record_size: 0x400000
          console_size: 0x200000
          ftrace_size: 0x100000
          pmsg_size: 0x100000
          max_reason: 2
          ecc: 16
          mem_type: 0
      pstore:
        force_cmdline: True
        params:
          backend: ramoops
          kmsg_bytes: 1

    # Compatibility for modular distro kernels. modprobe treats a built-in
    # ramoops as already satisfied in the intended config-debian-plus kernel.
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
    # which runs the pure install-kernel.sh compositor. Its children include
    # install-kernel-modprobe.sh (conditionally invokes install-kernel-cmdline.sh
    # for force_cmdline module params), install-kernel-params.sh (the raw
    # memmap= and log_buf_len= tokens). Panic policy is intentionally owned by
    # kernel-panic.etc.pb so storage layout and crash conversion do not conflict.
    # No SYSTEMD service: pstore writes kernel cmdline state and an efi_pstore
    # blacklist; a reboot or `sudo kernel-install` propagates cmdline to BLS.

    # /sys/fs/pstore records, surfaced by the generic status-dirs.sh reporter
    # (and by pstore-dump.sh, the focused human-readable readout). Should be
    # empty in steady state; non-empty after a crash.
    STATUS_DIRS:
      - /sys/fs/pstore
  tasks:
    - import_tasks: tasks/compfuzor.includes
