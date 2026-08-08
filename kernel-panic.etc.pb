---
- hosts: all
  vars:
    README: |
      # Kernel panic and crash capture policy

      > Converts otherwise silent kernel failures into bounded panics that the
      > pstore and, eventually, kdump capture layers can preserve.

      This playbook owns failure policy. `pstore.etc.pb` owns the persistent RAM
      storage layout. Keeping them separate makes it possible to change what
      becomes fatal without accidentally resizing or replacing crash evidence.

      ## Active policy

      The active baseline is deliberately narrower than "panic on everything":

      | Setting | Value | Reason |
      |---|---:|---|
      | `kernel.panic` | 10 | reboot ten seconds after panic instead of remaining hung forever |
      | `kernel.panic_on_oops` | 1 | convert a corrupted but limping kernel into a capturable panic |
      | `kernel.nmi_watchdog` | 1 | detect CPUs that stop servicing non-maskable interrupts |
      | `kernel.hardlockup_panic` | 1 | turn a detected hard CPU lockup into the panic capture path |
      | `kernel.softlockup_panic` | 1 | turn a CPU stuck in kernel context into the panic capture path |
      | `kernel.panic_sys_info` | `mem,all_bt,blocked_tasks` | append memory state, all-CPU stacks, and blocked tasks |

      Boot parameters duplicate the matching sysctls intentionally. They cover
      failures before `/etc/sysctl.d` is applied; sysctls provide live state,
      persistence, and drift reporting after userspace starts.

      ## Active parameters, individually

      `panic=10` and `kernel.panic=10` wait ten seconds and reboot after panic.
      This gives consoles time to flush and avoids an unattended machine staying
      dead indefinitely. Risk: automatic reboot removes the opportunity to read
      the screen live, so persistent capture must be verified before relying on
      it. A very short timeout can also race slow panic notifiers.

      `oops=panic` and `kernel.panic_on_oops=1` promote an oops or BUG from a
      warning-and-continue event to a panic. Continuing after an oops can create
      secondary corruption that hides the first fault. Risk: a recoverable driver
      oops now reboots the machine, causing availability loss and possible
      filesystem recovery. The original oops is retained because ramoops uses
      `max_reason=2`.

      `nmi_watchdog=panic,1` enables hard-lockup detection and asks the detector
      to panic. The runtime equivalents are `kernel.nmi_watchdog=1` and
      `kernel.hardlockup_panic=1`. This is high value when a CPU spins with
      interrupts disabled and cannot service the ordinary watchdog. Risk: the
      NMI watchdog permanently consumes one hardware performance counter and can
      very slightly perturb profiling or timing-sensitive workloads. Unsupported
      PMUs may not provide this detector.

      `softlockup_panic=1` and `kernel.softlockup_panic=1` panic when the kernel
      watchdog thread cannot run for the soft-lockup threshold. This captures
      long scheduler stalls and kernel loops that still receive timer interrupts.
      Risk: extreme overload, debugger stops, or pathological latency can become
      a forced reboot even when the system might eventually recover.

      `panic_sys_info=mem,all_bt,blocked_tasks` and the matching sysctl add memory
      state, all-CPU stack traces, and tasks blocked in uninterruptible sleep
      during panic. These often expose storage deadlocks, allocation
      failures, and the CPUs participating in a lock cycle. Risk: extra output
      lengthens panic processing and can push the original fault out of a small
      log. The pstore policy therefore retains one multi-megabyte ramoops record
      instead of the old 16 KiB record. Do not add console replay by default;
      replaying the entire printk ring can flood a slow console during panic.

      ## Deliberately inactive settings

      These are shown in the playbook as commented examples so their existence
      remains visible without silently making a workstation reboot on broad or
      noisy conditions.

      `kernel.hung_task_panic=1` would panic when a task remains in uninterruptible
      sleep beyond `kernel.hung_task_timeout_secs`. It can expose storage and
      driver deadlocks, but a slow or failing disk can cause legitimate long
      waits. Enable it for a focused reproduction after choosing a suitable
      timeout; do not make it the first global policy change.

      `kernel.panic_on_rcu_stall=1` with
      `kernel.max_rcu_stall_to_panic=1` would panic after the first detected RCU
      grace-period stall. This is useful for an RCU-specific investigation.
      Suspend, virtualization pauses, debugger stops, and severe overload can
      produce stalls, so it remains off in the baseline.

      `kernel.panic_on_warn=1` turns every `WARN()` into a reboot. WARN sites are
      intentionally used for conditions from severe corruption to recoverable
      driver quirks, making this too broad for normal operation. It is valuable
      in a controlled reproducer when a particular warning is the earliest clue.

      `vm.panic_on_oom=1` panics on selected out-of-memory events; value `2`
      panics even for constrained cpuset, mempolicy, or memcg OOMs. A normal OOM
      kill is usually recoverable, while a panic increases disruption. Use this
      only if the unexplained failure is specifically an OOM cascade and the
      memory image or complete allocation state is needed.

      `kernel.panic_on_unrecovered_nmi=1` and `kernel.panic_on_io_nmi=1` convert
      otherwise ignored unknown or I/O-error NMIs into panics. These can expose
      hardware faults but some platforms emit unusual benign NMIs. Enable only
      after confirming the machine's firmware and hardware behavior.

      `kernel.hardlockup_all_cpu_backtrace=1` and
      `kernel.softlockup_all_cpu_backtrace=1` request cross-CPU traces before the
      panic. `panic_sys_info=all_bt` already requests them in the final panic
      path. Asking twice adds NMI traffic and output at the worst possible time.

      `kernel.ftrace_dump_on_oops=1` dumps the volatile ftrace ring into printk.
      This can be enormous and overwrite the original report. The pstore policy
      instead reserves a persistent ftrace region that is explicitly activated
      only for targeted hang reproduction.

      ## Kdump and crashkernel

      Kdump is a separate capture layer atop the same panic trigger, not another
      pstore backend. The production kernel reserves a private memory range with
      `crashkernel=`, preloads a small capture kernel there using kexec, and jumps
      to it after panic. The capture kernel exposes the failed kernel's memory as
      `/proc/vmcore`; `makedumpfile` can then filter and write it to durable
      storage. A vmcore can reveal tasks, registers, locks, allocations, device
      state, and corrupted objects that a text log cannot.

      The kernel config already contains the important support: `KEXEC`,
      `KEXEC_FILE`, `CRASH_DUMP`, `PROC_VMCORE`, `RELOCATABLE`, debug information,
      kallsyms, and the ORC unwinder. That capability is dormant until all of the
      following exist:

      1. A boot reservation such as `crashkernel=512M`.
      2. A capture kernel and initramfs successfully loaded after every boot.
      3. A dump service such as Debian's `kdump-tools` plus `makedumpfile`.
      4. A destination the capture initramfs can access, including an explicit
         plan for encrypted storage.
      5. Matching unstripped `vmlinux`, modules, config, and source retained for
         every production kernel so the vmcore can be symbolized.

      `crashkernel=512M` is documented below but intentionally commented out.
      Reserving it now would permanently remove 512 MiB from normal use while no
      installed capture service consumes it. Once kdump is configured, 512 MiB
      is a sensible starting reservation for this 64 GiB x86-64 workstation;
      validate that the actual capture kernel loads and boots, then increase the
      reservation only if that measured environment requires it.

      The reservation stores the capture kernel and initramfs, not the vmcore.
      The dump destination must potentially handle a substantial fraction of
      64 GiB. `makedumpfile -l -d 31` normally removes free and cache pages and
      compresses what remains, but filtering is not a guaranteed maximum size.

      Default panic ordering enters kdump before panic notifiers and the final
      pstore dmesg callback. This maximizes the chance that the less-corrupted
      kernel can transition successfully. `CONFIG_PSTORE_CONSOLE=y` remains
      valuable because it writes continuously and retains text printed before
      that jump. Leave `crash_kexec_post_notifiers` unset: moving kdump later can
      improve the final ramoops dmesg but lets fragile panic notifiers prevent
      the much richer vmcore.

      After enabling kdump, treat `/sys/kernel/kexec/crash_loaded` equal to `1`
      as a required health check. A zero means the full-memory capture layer is
      absent even though `crashkernel=` may still be wasting reserved memory.

      ## Hardware watchdog

      The SP5100 TCO watchdog and `/dev/watchdog0` are present, but systemd's
      `RuntimeWatchdogSec` is currently off. A hardware watchdog is another
      separate layer: it resets a machine when userspace and the kernel stop
      making progress, even if no panic path can run. It does not create a vmcore.
      Continuous pstore console and optional persistent ftrace are the evidence
      most likely to survive that warm reset. Enable a runtime watchdog only
      after verifying the timeout, reboot behavior, and ramoops persistence.

      ## LKDTM

      LKDTM is the Linux Kernel Dump Test Module. It intentionally provokes
      panics, BUGs, exceptions, stack corruption, hangs, and other destructive
      failures so crash handling can be tested rather than merely assumed.
      `CONFIG_LKDTM=m` keeps this dangerous facility out of the normal kernel
      image until an administrator deliberately loads it.

      Start validation with SysRq-c, which exercises the ordinary panic path:

          sudo "$DIR/bin/status.sh"
          sudo sync
          sudo sh -c 'echo c > /proc/sysrq-trigger'

      LKDTM is for later maintenance-window tests of specific failure modes:

          sudo modprobe lkdtm
          echo PANIC | sudo tee /sys/kernel/debug/provoke-crash/DIRECT

      Every LKDTM action can lose unsynced data, wedge hardware, or expose an
      incomplete capture path. It is a diagnostic instrument, not a logger and
      not a service that should run continuously.

    # pstore ships no service and panic policy is kernel state, so generate only
    # kernel cmdline/sysctl artifacts and their normal install/apply/status bins.
    SYSTEMD_INSTALL_BYPASS: True
    SYSTEMD_THUNK_BYPASS: True

    # Boot-floor equivalents for failures before sysctl.d is applied.
    KERNEL_PARAMS:
      - "panic=10"
      - "oops=panic"
      - "nmi_watchdog=panic,1"
      - "softlockup_panic=1"
      - "panic_sys_info=mem,all_bt,blocked_tasks"

      # Awareness-only until kdump-tools, a tested capture initramfs, and a dump
      # destination are configured. Enabling this alone only wastes 512 MiB.
      # - "crashkernel=512M"

      # Keep kdump's safer default ordering. Running panic notifiers before the
      # crash-kexec jump can prevent the richer vmcore from being captured.
      # - "crash_kexec_post_notifiers=1"

    KERNEL_SYSCTL:
      # Bounded unattended recovery after the evidence writers run.
      kernel.panic: 10

      # A kernel that has oopsed is no longer trusted; preserve the first fault
      # and reboot rather than allowing secondary corruption to obscure it.
      kernel.panic_on_oops: 1

      # Hard-lockup detection consumes one PMU counter but catches CPUs that no
      # longer service ordinary interrupts.
      kernel.nmi_watchdog: 1
      kernel.hardlockup_panic: 1

      # Convert watchdog-detected kernel loops into the capture path. Extreme
      # latency can false-trigger this, so its risk is documented above.
      kernel.softlockup_panic: 1

      # High-value bounded context. Avoid console replay and full ftrace dumps,
      # which can displace the original failure even with the larger pstore.
      kernel.panic_sys_info: "mem,all_bt,blocked_tasks"

      # Awareness-only settings for focused investigations. Their false-positive
      # or blast-radius risks are too broad for the default workstation policy.
      # kernel.hung_task_panic: 1
      # kernel.panic_on_rcu_stall: 1
      # kernel.max_rcu_stall_to_panic: 1
      # kernel.panic_on_warn: 1
      # kernel.panic_on_unrecovered_nmi: 1
      # kernel.panic_on_io_nmi: 1
      # kernel.hardlockup_all_cpu_backtrace: 1
      # kernel.softlockup_all_cpu_backtrace: 1
      # kernel.ftrace_dump_on_oops: 1
      # vm.panic_on_oom: 1

  tasks:
    - import_tasks: tasks/compfuzor.includes
