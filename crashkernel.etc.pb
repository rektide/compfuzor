---
- hosts: all
  vars:
    README: |
      # Crashkernel and kdump

      > Reserve a protected capture environment that can save the failed
      > kernel's memory as a vmcore after panic.

      ## What this adds

      Pstore preserves bounded text and trace rings in persistent RAM. Kdump is
      a separate, richer layer: the production kernel reserves memory that it
      will never use, `kdump-tools` loads a small capture kernel into that memory,
      and panic transfers control to the capture kernel with the failed kernel's
      RAM left intact. The capture kernel exposes that memory as `/proc/vmcore`;
      `makedumpfile` filters and writes it to durable storage.

      A vmcore can answer questions that a panic log usually cannot:

      - Which tasks, locks, workqueues, and CPUs were involved?
      - What did driver and allocator data structures contain?
      - Was memory corrupted before the visible panic?
      - What code and registers were active on CPUs that printed nothing?

      Kdump has more dependencies and more failure modes than ramoops. Keep both.
      Ramoops is the small fallback and preserves continuously written console
      text across some warm resets. Kdump is the preferred full forensic artifact
      when panic can successfully start the capture kernel.

      ## What the playbook owns

      The playbook adds `crashkernel=512M` to `/etc/kernel/cmdline`, installs the
      Debian capture and analysis tools, and relies on the existing kernel/BLS
      compositor to propagate the reservation to boot entries.

      This ownership model targets this host's systemd-boot/BLS setup. Debian's
      package also installs `/etc/default/grub.d/kdump-tools.cfg` with its own
      `crashkernel=512M-:192M` range. Systemd-boot ignores that file. A GRUB host
      must remove or override the package fragment so it does not silently reserve
      192 MiB instead of this playbook's reviewed 512 MiB policy.

      It does not choose a final dump filesystem, remote target, retention count,
      or encryption-unlock mechanism. Those decisions control whether a vmcore
      can actually be saved and how much sensitive memory is retained. Package
      first installation is deliberately preseeded with `USE_KDUMP=0`: tools are
      present, but a new capture service cannot arm against an unsafe destination.
      Debconf does not override an existing `/etc/default/kdump-tools`, so an
      already-installed host must be inspected and disarmed explicitly.

      ## Why 512 MiB

      `crashkernel=512M` asks the kernel to remove 512 MiB from normal allocation
      and keep it available for the capture kernel and initramfs. It does not
      store the vmcore itself. On this 64 GiB workstation the nominal reservation
      costs about 0.8% of RAM and gives a custom kernel, initramfs, storage
      drivers, and dump tools useful margin.

      On x86-64, automatic placement first tries below 4 GiB. If 512 MiB cannot
      fit there, the main reservation may be placed high and the kernel can add a
      separate low-memory reservation, commonly 256 MiB. The total cost can then
      be about 768 MiB. Verify the actual low/high reservations in the boot log
      and `/proc/iomem` instead of assuming exactly 512 MiB.

      The required reservation depends more on the capture kernel, decompressed
      initramfs, loaded drivers, CPU count, and dump path than on the failed
      kernel's total RAM. After installation and the next boot,
      `kdump-config show` can report the package's estimate using the generated
      initramfs size and early memory snapshot. Reduce 512 MiB only after the real
      capture environment repeatedly loads and boots; increase it if the
      estimator or journal reports insufficient reserved memory.

      Avoid an explicit `@offset` unless automatic placement fails. On x86-64,
      the kernel searches for a suitable reservation and handles low/high-memory
      constraints. Avoid `crashkernel=...,cma` for forensic capture because DMA
      can reuse or corrupt pages that the second kernel needs to inspect.

      ## Packages

      `kdump-tools` supplies the Debian service, capture initramfs integration,
      Debian kernel post-install/removal hooks, `kdump-config`, local/remote save
      logic, and dmesg extraction.

      `kexec-tools` loads and enters the capture kernel. It is a hard dependency
      of `kdump-tools`, but is declared explicitly because it is the transition
      mechanism being configured.

      `makedumpfile` reads `/proc/vmcore`, removes unneeded page classes, and
      produces a compressed dump. Debian recommends it rather than blindly
      copying a raw image that can approach installed RAM size.

      `initramfs-tools-core` supplies `mkinitramfs`, which Debian's kernel hook
      uses to build the minimal capture initramfs. It is only a recommendation of
      `kdump-tools`, so the playbook declares it for hosts that disable automatic
      installation of recommended packages.

      `crash` is the postmortem analysis shell. It combines the vmcore with the
      exact matching unstripped `vmlinux` to inspect tasks, stacks, memory,
      structures, logs, and disassembly.

      Package installation alone is not proof that capture works. The running
      service must successfully load a crash kernel after every production boot.

      ## Kernel requirements

      The production and capture kernels require the kexec/kdump facilities.
      `config-debian-plus` already contains the relevant support:

          CONFIG_KEXEC=y
          CONFIG_KEXEC_FILE=y
          CONFIG_CRASH_DUMP=y
          CONFIG_PROC_VMCORE=y
          CONFIG_RELOCATABLE=y
          CONFIG_DEBUG_INFO=y
          CONFIG_KALLSYMS=y

      `CONFIG_KEXEC_SIG` matters under Secure Boot: the crash kernel must satisfy
      the production kernel's signature policy. A reservation can exist while
      loading still fails because the image is unsigned or its key is untrusted.

      Preserve these artifacts for every installed production kernel:

      - the exact unstripped `vmlinux`
      - all matching modules and their debug information
      - the final kernel config
      - the source revision and local patches
      - the compiler and linker identity

      A vmcore without matching symbols remains partially useful, but structure
      layouts and reliable source-level stacks depend on exact build artifacts.

      ## Debian capture defaults and arming gate

      Debian's `kdump-tools` configuration lives in
      `/etc/default/kdump-tools`. The playbook preseeds `USE_KDUMP=0` for a new
      installation; do not change it to `1` until storage, capture command line,
      and retention have been reviewed. Preseeding is not an idempotent disarm:
      an existing configuration file remains authoritative. Other current
      package defaults include:

          KDUMP_COREDIR=/var/crash
          KDUMP_DUMP_DMESG=1
          MAKEDUMP_ARGS="-F -c -d 31"
          KDUMP_CMDLINE_APPEND="reset_devices systemd.unit=kdump-tools-dump.service nr_cpus=1 irqpoll usbcore.nousb"

      `USE_KDUMP=0` prevents the service from loading a capture kernel. This is
      the safe initial state, not a functioning capture state. Once the remaining
      policy is ready, set `USE_KDUMP=1`, restart `kdump-tools.service`, and
      require `crash_loaded=1`.

      `KDUMP_COREDIR=/var/crash` is not safe on the current highly utilized root
      filesystem. If the filtering pipeline reports failure, Debian retries by
      copying the raw vmcore, which can approach 64 GiB; retention cleanup happens
      only after a reported successful save. The package pipeline does not use
      `pipefail`, so a late `makedumpfile` failure can also leave a truncated file
      marked complete. Provision a raw-memory-capacity dedicated filesystem or
      authenticated remote target before setting `USE_KDUMP=1`, and verify every
      resulting artifact opens successfully with its analysis tool.

      `KDUMP_DUMP_DMESG=1` saves an extracted kernel log alongside the vmcore.
      Keep it enabled: it is small, immediately readable, and useful even when
      later vmcore analysis fails.

      `MAKEDUMP_ARGS="-F -c -d 31"` requests flattened, compressed output while
      excluding zero, cache, cache-private, userspace, and free pages. This often
      shrinks a workstation dump dramatically, but it does not guarantee a size.
      Kernel-owned pages can still be large, and excluded userspace pages may
      remove evidence needed for a particular investigation.

      `KDUMP_CMDLINE_APPEND` applies only to the capture kernel. `reset_devices`
      asks drivers to recover hardware left in an unknown state; `nr_cpus=1`
      reduces capture memory and complexity; `irqpoll` helps when interrupt
      routing is damaged; `usbcore.nousb` avoids fragile USB initialization. Do
      not put these arguments in the production kernel command line.

      Debian starts from `/proc/cmdline` and strips only a small set of options.
      Without an explicit `KDUMP_CMDLINE`, the capture kernel inherits production
      triggers such as `oops=panic`, `nmi_watchdog=panic,1`, and
      `softlockup_panic=1`, plus ramoops parameters. A driver oops could then
      panic the capture kernel before it saves anything, while capture-kernel
      pstore writes could overwrite the original ramoops evidence.

      Before arming, define `KDUMP_CMDLINE` in `/etc/default/kdump-tools` by
      retaining the production command line except these capture-hostile tokens:

          crashkernel=*
          panic=*
          oops=*
          nmi_watchdog=*
          softlockup_panic=*
          panic_sys_info=*
          pstore.*
          ramoops.*
          memmap=*
          log_buf_len=*

      Preserve root, storage, console, architecture, and device-discovery options
      required by the capture initramfs. Then let `KDUMP_CMDLINE_APPEND` add the
      package's `reset_devices`, single-CPU, `irqpoll`, and dump-service options.
      Also add capture-environment sysctl overrides under `/etc/kdump/sysctl.conf`
      for `kernel.panic_on_oops=0`, `kernel.hardlockup_panic=0`, and
      `kernel.softlockup_panic=0`. The package applies these after initramfs boot;
      filtering the early boot parameters remains necessary.

      `KDUMP_NUM_DUMPS` defaults to unlimited retention. Choose a limit or an
      externally managed retention policy before repeated crash testing. Cleanup
      after a completed dump cannot prevent the in-progress dump from filling the
      destination, so free-space monitoring remains necessary. This variable only
      prunes local dumps; NFS, SSH, and FTP targets require independent
      server-side retention and capacity controls.

      `KDUMP_FAIL_CMD` defaults effectively to forced reboot. An interactive
      shell can help diagnose capture-kernel failures but leaves the machine
      unattended and requires a usable console. Keep forced reboot unless a
      maintenance test has an operator present.

      Debian's loader also sets production `kernel.panic_on_oops=1` whenever it
      successfully arms kdump. That agrees with `kernel-panic.etc.pb`, but it is
      a package-enforced exception to that playbook's policy ownership.

      The playbook deliberately does not replace this package-owned file. Debian
      can evolve version-specific defaults, while dump destination, retention,
      remote credentials, and encrypted storage require an explicit host policy.

      ## Storage and confidentiality

      A raw vmcore can approach 64 GiB. Filtered dumps are commonly much smaller,
      but reserve enough space for the largest credible kernel-owned working set
      plus a failed or partial previous dump. A dedicated 128 GiB destination is
      a reasonable starting point when one raw-memory-class dump must fit with
      operational margin.

      Vmcores can contain credentials, encryption keys, messages, documents,
      network payloads, and application memory. Treat the destination as highly
      sensitive: root-only permissions, encryption at rest, bounded retention,
      and controlled export are required.

      An encrypted root filesystem creates a bootstrapping problem. The capture
      initramfs must be able to unlock the dump destination without an unavailable
      desktop session or interactive prompt. A separate encrypted dump target,
      reserved-key handoff, or authenticated remote destination needs to be
      tested explicitly; otherwise kdump can appear armed but fail only after the
      real crash. Reserved dm-crypt key handoff requires
      `CONFIG_CRASH_DM_CRYPT=y`; it is currently disabled in
      `config-debian-plus`, so that path requires a future kernel rebuild.

      ## Panic ordering with pstore

      Normal panic ordering attempts crash-kexec before late panic notifiers and
      the final pstore dmesg callback. This gives the less-corrupted kernel the
      best chance of starting the richer capture environment. It also means a
      successful kdump may preempt the final ramoops dmesg snapshot.

      `CONFIG_PSTORE_CONSOLE=y` remains valuable because console pstore is written
      continuously before panic. If kdump is absent or returns after failure, the
      normal panic path continues and ramoops can still receive dmesg.

      Do not add `crash_kexec_post_notifiers=1` by default. It moves kdump after
      notifiers and the pstore dumper, but any broken notifier can then prevent
      the full vmcore transition. Prefer kdump reliability over a redundant final
      dmesg record.

      ## Installation sequence

      Running the Ansible playbook installs the declared packages immediately,
      with a new installation disarmed through debconf, and generates this
      subsystem under `/etc/opt/crashkernel-main`. If kdump-tools was already
      installed, first set `USE_KDUMP=0`, restart the service, run
      `kdump-config unload`, and verify both crash-loaded sysfs values are zero.

      The playbook does not execute the generated kernel installer. To write
      `/etc/kernel/cmdline` and regenerate the running kernel's systemd-boot
      entry, explicitly run:

          sudo KERNEL_INSTALL=1 /etc/opt/crashkernel-main/bin/install.sh

      Without `KERNEL_INSTALL=1`, compfuzor updates the canonical cmdline but
      deliberately skips BLS regeneration. The reservation takes effect only
      after booting an entry that actually contains `crashkernel=512M`.

      Package installation, memory reservation, dump-policy review, arming, and
      destructive testing are separate operator decisions. This playbook does
      not collapse them into one action.

      ## Verification after installation

      A reservation, installed package, armed service, and loaded capture
      kernel are four different states. Check all of them after every new kernel:

          grep -o 'crashkernel=[^ ]*' /proc/cmdline
          grep -i 'Crash kernel' /proc/iomem
          systemctl status kdump-tools.service --no-pager
          kdump-config show
          kdump-config status
          cat /sys/kernel/kexec/crash_loaded

      The final value must be `1` after deliberate arming. A value of `0` is
      expected while `USE_KDUMP=0`; after arming it means the kernel-memory vmcore
      capture layer is absent even if memory remains reserved. Review the service
      journal for initramfs, signature, memory, or driver errors:

          journalctl -b -u kdump-tools.service --no-pager

      Also verify `/var/lib/kdump/vmlinuz` and `/var/lib/kdump/initrd.img` resolve
      to the intended kernel artifacts, and verify free space on the configured
      dump destination.

      ## Controlled validation

      Do not make an intentional crash until pstore has passed its own smoke test,
      `crash_loaded` is `1`, the dump destination is writable from the capture
      environment, and matching debug artifacts have been retained.

      In a maintenance window, sync filesystems and use SysRq-c:

          sudo sync
          sudo sh -c 'echo c > /proc/sysrq-trigger'

      The machine should boot the capture kernel, save dmesg and vmcore, reboot,
      then load a fresh capture kernel for the new production boot. Confirm the
      resulting artifact and re-check `crash_loaded=1`; one successful dump does
      not prove the next kernel update remained armed.

      Analyze a dump using its exact matching unstripped kernel:

          crash /path/to/vmlinux /var/crash/<dump>/dump.<timestamp>

      LKDTM tests belong after basic SysRq capture works. They exercise more
      pathological paths but add no value until the ordinary pipeline is proven.

    # Do not execute generated commands during playbook generation. PKGS are
    # installed by Ansible; kernel/BLS installation remains an explicit action.
    BINS_RUN_BYPASS: True

    # Preseed new package installation without arming it against Debian's unsafe
    # unlimited /var/crash default. Existing config still requires inspection.
    DEBCONF:
      - name: kdump-tools
        question: kdump-tools/use_kdump
        vtype: boolean
        value: "false"

    PKGS:
      - kdump-tools
      - kexec-tools
      - makedumpfile
      - initramfs-tools-core
      - crash

    # Reserve memory in the production kernel. Capture-only arguments such as
    # nr_cpus=1 and irqpoll belong to KDUMP_CMDLINE_APPEND, not here.
    KERNEL_PARAMS:
      - "crashkernel=512M"

  tasks:
    - import_tasks: tasks/compfuzor.includes
