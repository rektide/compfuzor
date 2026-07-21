---
- hosts: all
  vars:
    README: |
      # pstore/ramoops

      > Captures kernel oops/panic logs in reserved RAM that survives reboot.

      ## Three pieces, all required

      Ramoops silently fails if any one of these is missing. The original
      version of this playbook only did piece #2, which is why pstore never
      actually captured anything.

      1. **Reserved physical RAM** via `memmap=` on the kernel cmdline. The
         region is excluded from normal kernel allocation and survives reboot.
         Without this, ramoops has nothing stable to write to across reset.

      2. **ramoops module params** (`mem_address`, `mem_size`, …) pointing at
         that reservation. On a modular kernel, ramoops loads from initramfs
         before `/etc/modprobe.d/` is parsed, so these MUST reach it via the
         kernel cmdline as `ramoops.<param>=<value>` tokens. `setup.sh` calls
         `install-kernel-cmdline.sh` directly to write them there, bypassing
         the framework's built-in-vs-module detection in `install-kernel.sh`
         (which would otherwise route modular ramoops to modprobe.d only).

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

      After running this playbook, run `sudo "$DIR/bin/setup.sh"` (or rely on
      the oneshot systemd unit). Then on the next boot:

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

    # ramoops + pstore.backend flow through compfuzor's kernel_modprobe
    # subsystem, which makes install-kernel-cmdline.sh available. setup.sh
    # invokes it to write these as <module>.<param>=<value> tokens on the
    # kernel cmdline (the form ramoops actually reads at probe time).
    KERNEL_MODULES:
      ramoops:
        params:
          mem_address: "{{RAMOOPS_MEM_ADDRESS}}"
          mem_size: "{{RAMOOPS_MEM_SIZE}}"
          record_size: 0x4000
          console_size: 0x20000
          ftrace_size: 0x10000
          pmsg_size: 0x10000
          ecc: 0
      pstore:
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

    # oneshot setup: push KERNEL_MODULES params to /etc/kernel/cmdline (calling
    # install-kernel-cmdline.sh directly, NOT install-kernel.sh — the latter
    # would route modular ramoops to /etc/modprobe.d only, which doesn't apply
    # during initramfs-load), then add the raw memmap= reservation token that
    # the framework's <module>.<param> generator cannot express.
    SYSTEMD_SERVICE: True
    SYSTEMD_TYPE: oneshot
    SYSTEMD_EXEC: "{{DIR}}/bin/setup.sh"
    BINS:
      - name: setup.sh
        content: |
          #!/bin/sh
          set -eu

          # 1. Push KERNEL_MODULES into /etc/kernel/cmdline as
          #    <module>.<param>=<value> tokens. Idempotent (script replaces
          #    existing same-key tokens in place, appends new ones).
          "$DIR/bin/install-kernel-cmdline.sh"

          # 2. Add the raw memmap= reservation. install-kernel-cmdline.sh only
          #    handles <module>.<param>=<value> tokens, so memmap= needs its
          #    own idempotent append.
          _cmdline_file=/etc/kernel/cmdline
          _token='memmap={{RAMOOPS_MEM_SIZE}}${{RAMOOPS_MEM_ADDRESS}}'

          sudo mkdir -p "$(dirname "$_cmdline_file")"
          sudo touch "$_cmdline_file"
          _existing="$(sudo cat "$_cmdline_file")"

          # Idempotent: if our exact token is already present, nothing to do.
          for _tok in $_existing; do
            [ "$_tok" = "$_token" ] && exit 0
          done

          # Refuse to clobber a different memmap= pointing at our address
          # (likely a size change — needs human eyes).
          if printf '%s\n' "$_existing" | grep -Eq "memmap=[^[:space:]]+[\\\$]{{RAMOOPS_MEM_ADDRESS}}"; then
            echo "pstore: a different memmap= token exists for {{RAMOOPS_MEM_ADDRESS}} in $_cmdline_file; fix manually" >&2
            exit 1
          fi

          # Append, normalize whitespace.
          _updated="$(printf '%s %s' "$_existing" "$_token" | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//')"
          printf '%s\n' "$_updated" | sudo tee "$_cmdline_file" >/dev/null

          echo "pstore: wrote $_token to $_cmdline_file"
          echo "pstore: run 'sudo kernel-install' for the current kernel, or reboot, to propagate to BLS entries"

    # /sys/fs/pstore records, surfaced by the generic status-dirs.sh reporter.
    # Should be empty in steady state; non-empty after a crash.
    STATUS_DIRS:
      - /sys/fs/pstore
  tasks:
    - import_tasks: tasks/compfuzor.includes
