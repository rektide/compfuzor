---
- hosts: all
  vars:
    TOOL_VERSIONS:
      nodejs: True

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
         `install-kernel-modprobe.sh` to use the cmdline path (not modprobe.d)
         regardless of built-in detection.

      3. **`pstore.backend=ramoops`** plus **blacklist efi_pstore**. pstore
         permits exactly one backend; `efi_pstore` autoprobes very early via
         systemd's module autoload and wins the slot. `pstore.backend=` pins
         the choice on the cmdline; the modprobe blacklist stops efi_pstore
         from even loading — belt and suspenders.

      4. **A non-empty dmesg region.** Ramoops subtracts `console_size`,
         `ftrace_size`, and `pmsg_size` from `mem_size` before dividing the
         remainder into `record_size` crash records. The remainder must be at
         least one record. `status-ramoops.sh` checks this arithmetic because
         the backend can register successfully with zero dmesg records.

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
          sudo "$DIR/bin/status-ramoops.sh"           # registration and dmesg layout are usable
          ls /sys/fs/pstore/                         # empty until a crash

      ## Crash-testing

      Once ramoops is winning (verified above), crash-test it. Two prerequisites
      make this hands-off:

      1. **`kernel.panic` > 0** -- declared below via `KERNEL_SYSCTL`, so it is
         persisted (`install-kernel-sysctl.sh`), applied live
         (`apply-kernel-sysctl.sh`), and
         drift-checked (`status-sysctl.ts`). With the default `0` a panic *hangs
         forever* and you must hold the power button to recover; with it set, the
         kernel auto-reboots after N seconds, so the test is unattended and
         ramoops (which flushes at panic time) still captures.
      2. **At least one dmesg record** -- `status-ramoops.sh` must report a
         positive dmesg byte and record count. Registration alone does not
         prove this.

      Writing `/proc/sysrq-trigger` as root is always allowed; `kernel.sysrq`
      only controls keyboard-triggered SysRq. Do not broaden that mask just for
      this test.

      Then trigger a fault and read the capture on the next boot:

      | Method | Trigger                                  | Reproduces         | Captured? | Why                                        |
      |--------|------------------------------------------|--------------------|-----------|--------------------------------------------|
      | A      | `echo c > /proc/sysrq-trigger`           | clean panic + trace| yes       | panic kmsg dumper writes the dmesg record  |
      | B      | `echo b > /proc/sysrq-trigger`           | instant reset      | console only | requires `CONFIG_PSTORE_CONSOLE=y`         |
      | C      | hold power button / yank power           | abrupt power loss  | console only | requires continuously written console data |
      | D      | LKDTM `LOOP`                             | hard lockup        | conditional | also needs NMI watchdog + hardlockup panic |

      Method A is the recommended first smoke test. It proves panic capture,
      persistence, reboot, and recovery; it does not reproduce the original
      crash trigger. Sync first to reduce unrelated filesystem recovery:

          sudo "$DIR/bin/status-ramoops.sh"
          sudo sync
          sudo sh -c 'echo c > /proc/sysrq-trigger' # panic; kernel.panic reboots it

      With `kernel.panic` set this self-reboots (no power button). On the next
      boot, read and clear the capture:

          journalctl -b -u systemd-pstore --no-pager # confirm early-boot archival
          sudo "$DIR/bin/pstore-dump.sh"             # live and archived records

      `systemd-pstore` normally moves records from `/sys/fs/pstore` into
      `/var/lib/systemd/pstore` and unlinks the originals early during boot.
      An empty live directory after boot therefore does not prove capture
      failed; use the readout above.

      B and C (the abrupt-death case ramoops exists for) won't capture with the
      current kernel: only `PSTORE_RAM` is on, so capture is panic-triggered.
      To cover power-loss / hard-reset, rebuild with `CONFIG_PSTORE_CONSOLE=y`
      (continuously mirrors the console to ramoops) or `CONFIG_LKDTM=m`
      (method D, which panics via the watchdog).

          grep -E 'PSTORE_RAM|PSTORE_CONSOLE|PSTORE_PMSG|PSTORE_FTRACE|LKDTM' /boot/config-$(uname -r)

      ## Why this exists at all

      `efi_pstore` writes crash records to EFI variables. It works for *clean*
      panics but is unreliable for hard resets, OOM-kill cascades, or any fault
      where the firmware doesn't get a clean write window to EFI vars — exactly
      the cases you most want captured. Ramoops writes to reserved RAM that the
      firmware doesn't touch on reset, so it survives those scenarios.

      `PSTORE_CONSOLE`, `PSTORE_PMSG`, and `PSTORE_FTRACE` are compile-time
      kernel options (not modules). If your kernel was built without them, the
      `console_size`, `pmsg_size`, and `ftrace_size` params below are accepted
      and reserved but those buffers will never be written to. Their sizes are
      still subtracted from the dmesg budget, so the total reservation must
      explicitly leave room for panic/oops records.

          grep -E 'PSTORE_RAM|PSTORE_CONSOLE|PSTORE_PMSG|PSTORE_FTRACE' /boot/config-$(uname -r)

    # pstore ships no systemd service -- opt out explicitly (SYSTEMD_BYPASS
    # alone only skips the thunk, not unit generation).
    SYSTEMD_INSTALL_BYPASS: True
    SYSTEMD_THUNK_BYPASS: True

    # Physical address reserved for ramoops. Default works on any x86_64 with
    # ≥ 8 GB RAM (4 GB boundary, above BIOS MMIO holes). Override per-host
    # via -e RAMOOPS_MEM_ADDRESS=0x... for unusual layouts.
    RAMOOPS_MEM_ADDRESS: "0x100000000"
    # 512 KB total: 256 KB dmesg + 128 KB console + 64 KB ftrace + 64 KB pmsg.
    # With 16 KB records, the dmesg region retains sixteen crashes.
    RAMOOPS_MEM_SIZE: "0x80000"

    # Raw kernel cmdline tokens that don't fit the <module>.<param> shape.
    # install-kernel-params.sh writes these to /etc/kernel/cmdline
    # idempotently (replace by key prefix, append if absent).
    KERNEL_PARAMS:
      - "memmap={{RAMOOPS_MEM_SIZE}}${{RAMOOPS_MEM_ADDRESS}}"

    # force_cmdline: True on each entry forces install-kernel-modprobe.sh to emit
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

    # kernel.panic: seconds before auto-reboot on panic (0 = hang forever).
    # Declared (not optional) for two reasons: (1) crash-testing -- with 0 an
    # `echo c` panic hangs and you must power-cycle; with >0 the box self-reboots
    # unattended and ramoops still flushes at panic time. (2) drift visibility --
    # declaring it makes status-sysctl.ts flag a regression to 0.
    # install-kernel-sysctl.sh persists it to /etc/sysctl.d;
    # apply-kernel-sysctl.sh sets it live. A boot-floor
    # cmdline token (`panic=N` via KERNEL_PARAMS) is a redundant option if you
    # want it set before any apply runs; sysctl alone is enough here.
    KERNEL_SYSCTL:
      kernel.panic: 10

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
    # memmap= token), and install-kernel-sysctl.sh (kernel.panic persistence).
    # No SYSTEMD service: pstore only writes /etc/kernel/cmdline + a sysctl drop;
    # a reboot or `sudo kernel-install` propagates cmdline to BLS entries.

    # /sys/fs/pstore records, surfaced by the generic status-dirs.sh reporter
    # (and by pstore-dump.sh, the focused human-readable readout). Should be
    # empty in steady state; non-empty after a crash.
    STATUS_DIRS:
      - /sys/fs/pstore
  tasks:
    - import_tasks: tasks/compfuzor.includes
