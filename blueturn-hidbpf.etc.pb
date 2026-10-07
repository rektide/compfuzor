---
- hosts: all
  vars:
    TYPE: blueturn-hidbpf
    # eBPF stopgap for the iRig BlueTurn pedal on the 7.1.0-debplus kernel:
    # the pedal sends 7-byte boot-keyboard reports against an 8-byte Report
    # Map, and hid-core's uhid path drops short reports (v7.0 regression,
    # fixed v7.1.4+/7.2 -- design/blueturn/kernel-uhid-shortreport.general.md).
    # This HID-BPF program pads 7->8 at the device_event hook -- the exact
    # semantics the kernel used to apply -- and udev-hid-bpf auto-attaches
    # it to every new uhid instance (the pedal churns instances on each BLE
    # reconnect, so per-device manual attach is whack-a-mole).
    # Build notes: struct_ops layout must match the RUNNING kernel, so
    # vmlinux.h is generated from /sys/kernel/btf/vmlinux each build (the
    # udev-hid-bpf checkout's copy drifts with upstream); kernel-BTF kfunc
    # decls can conflict with the installed libbpf headers -- build.sh
    # strips conflicting declarations and retries. And struct_ops programs
    # MUST carry a GPL license section (missing license = EINVAL on load).
    PKGS:
      - udev-hid-bpf
      - clang
      - libbpf-dev
      - bpftool
    BINS:
      - name: build.sh
        content: |
          # compile blueturn.bpf.c against the RUNNING kernel's BTF
          SRC="$DIR/blueturn.bpf.c"
          OUT="$DIR/blueturn.bpf.o"
          UHB="${UDEV_HID_BPF_HEADERS:-/usr/local/src/udev-hid-bpf-git/repo/src/bpf}"
          [ -d "$UHB" ] || UHB="$HOME/archive/libevdev/udev-hid-bpf/src/bpf"
          [ -d "$UHB" ] || { echo "no udev-hid-bpf headers (apply udev-hid-bpf.src.pb or dl the repo)"; exit 1; }
          bpftool btf dump file /sys/kernel/btf/vmlinux format c > "$DIR/vmlinux.h"
          CLANG=(clang -std=gnu11 -fno-stack-protector -O2 -target bpf -g -c
            -fms-extensions -Wno-microsoft-anon-tag -D__TARGET_ARCH_x86
            -I"$DIR" -I"$UHB" -o "$OUT" "$SRC")
          # kernel-BTF vmlinux.h may declare kfuncs the installed libbpf
          # headers also declare (e.g. bpf_stream_vprintk): strip each
          # conflicting declaration from vmlinux.h and retry
          for _ in 1 2 3 4 5 6; do
            if err=$("${CLANG[@]}" 2>&1); then
              echo "built $OUT against $(uname -r)"
              exit 0
            fi
            sym=$(printf '%s\n' "$err" | sed -n "s/.*conflicting types for '\([^']*\)'.*/\1/p" | head -1)
            if [ -z "$sym" ]; then
              printf '%s\n' "$err" >&2
              exit 1
            fi
            echo "stripping libbpf-conflicting kfunc decl from vmlinux.h: $sym"
            sed -i "/extern [^;]*\b$sym\b/d" "$DIR/vmlinux.h"
          done
          echo "gave up stripping conflicting kfuncs" >&2
          exit 1
      - name: install.sh
        run: true
        become: true
        content: |
          # rebuild (per-kernel vmlinux.h) + install + arm auto-attach
          "$DIR/bin/build.sh"
          udev-hid-bpf install --force "$DIR/blueturn.bpf.o"
          udevadm control --reload
          # attach to the live instance too, if the pedal is connected
          for hid in /sys/bus/hid/devices/0005:0214:0002.*; do
            [ -d "$hid" ] || continue
            udev-hid-bpf add "$hid" "$DIR/blueturn.bpf.o" 2>/dev/null || true
          done
          echo "installed; udev will auto-attach on every reconnect"
      - name: watch-blueturn.sh
        content: |
          # live pedal key events, no time windows: run, press when ready, Ctrl-C
          #   watch-blueturn.sh       kanata OUTPUT keyboards (what wev receives)
          #   watch-blueturn.sh raw   pedal's RAW node (pauses kanata-blueturn,
          #                           restarts it on exit) -- true keycodes
          blueturn_node() {
            awk '/N: Name="iRig BlueTurn Keyboard"/{ok=1} ok && /^H: Handlers/{for(i=1;i<=NF;i++) if($i ~ /^event[0-9]+$/){print "/dev/input/" $i; exit}}' /proc/bus/input/devices
          }
          kanata_nodes() {
            awk '/N: Name="kanata"/{ok=1;next} ok && /^H: Handlers/{for(i=1;i<=NF;i++) if($i ~ /^event[0-9]+$/){print "/dev/input/" $i; ok=0}}' /proc/bus/input/devices
          }
          command -v evtest >/dev/null || { echo "evtest missing (apt install evtest)"; exit 1; }
          if [ "$1" = "raw" ]; then
            node="$(blueturn_node)"
            [ -n "$node" ] || { echo "no iRig hid node (pedal disconnected?)"; exit 1; }
            echo "== raw pedal node: $node =="
            sudo systemctl stop kanata-blueturn.service 2>/dev/null || true
            trap 'echo; echo "(restarting kanata-blueturn)"; sudo systemctl start kanata-blueturn.service 2>/dev/null || true' EXIT INT TERM
            exec sudo evtest "$node"
          else
            echo "== kanata uinput outputs (press pedals; ignore lines from typing) =="
            pids=""
            cleanup() { echo; [ -n "$pids" ] && kill $pids 2>/dev/null || true; wait 2>/dev/null || true; }
            trap cleanup EXIT INT TERM
            i=0
            for n in $(kanata_nodes); do
              i=$((i+1))
              ( sudo evtest "$n" 2>/dev/null | sed "s|^|[kanata-$i $n] |" ) &
              pids="$pids $!"
            done
            wait
          fi
      - name: watch-btmon.sh
        content: |
          # HCI-level trace of the pedal's BLE link: connect/disconnect
          # cycles with REASON CODES (who kills the bearer). Run, wake/press
          # the pedal, Ctrl-C; full log path printed at exit.
          LOG="${1:-/home/rektide/tmp-opencode/btmon-$(date +%H%M%S).txt}"
          echo "== btmon -> $LOG (Ctrl-C to stop; filtered view below) =="
          sudo btmon > "$LOG" 2>&1 &
          pid=$!
          trap 'echo; echo "full log: $LOG"; sudo kill '"$pid"' 2>/dev/null || true' EXIT INT TERM
          sudo stdbuf -o0 tail -f "$LOG" | rg --line-buffered -i 'disconnect|reason|le connection|connect complete|encryption|pairing'
    ETC_FILES:
      - name: blueturn.bpf.c
        content: |
          // SPDX-License-Identifier: GPL-2.0-only
          /* iRig BlueTurn (IK Multimedia) BLE footpedal: 0005:0214:0002
           *
           * The pedal's firmware sends its boot-keyboard input report as
           * 7 bytes while its Report Map declares 8 (mod, reserved, k0..k5).
           * Kernels v7.0..v7.1.3 dropped short reports outright in
           * hid_report_raw_event for the uhid bus ("Event data for report 0
           * was too short (8 vs 7)"); <=6.19 zero-padded the tail and
           * v7.1.4+/v7.2 restore that (backport cfc0d283d931 / commit
           * 63a694c51bf1). This program restores the same
           * append-trailing-zero semantics at the device_event hook so the
           * pedal works on affected kernels.
           */

          #include "vmlinux.h"
          #include "hid_bpf.h"
          #include "hid_bpf_helpers.h"
          #include <bpf/bpf_tracing.h>

          #define VID_IK_MULTIMEDIA 0x0214
          #define PID_BLUETURN 0x0002

          HID_BPF_CONFIG(
          	HID_DEVICE(BUS_BLUETOOTH, HID_GROUP_GENERIC, VID_IK_MULTIMEDIA, PID_BLUETURN)
          );

          #define KEYBOARD_REPORT_SIZE 8

          SEC(HID_BPF_DEVICE_EVENT)
          int BPF_PROG(blueturn_pad_report, struct hid_bpf_ctx *hctx)
          {
          	__u8 *data;

          	if (hctx->size != KEYBOARD_REPORT_SIZE - 1)
          		/* full-size reports (and the numbered consumer report)
          	 * pass through untouched */
          		return 0;

          	data = hid_bpf_get_data(hctx, 0, KEYBOARD_REPORT_SIZE);
          	if (!data)
          		return 0; /* EPERM check */

          	data[KEYBOARD_REPORT_SIZE - 1] = 0x00;
          	hctx->size = KEYBOARD_REPORT_SIZE;

          	return 0;
          }

          /* struct_ops programs are GPL-only: a missing license section
           * fails BPF_PROG_LOAD with EINVAL (cost an hour to find) */
          char _license[] SEC("license") = "GPL";

          HID_BPF_OPS(blueturn) = {
          	.hid_device_event = (void *)blueturn_pad_report,
          };

          SEC("syscall")
          int probe(struct hid_bpf_probe_args *ctx)
          {
          	ctx->retval = 0;

          	return 0;
          }
      - name: README.md
        content: |
          # blueturn-hidbpf

          eBPF stopgap that makes the iRig BlueTurn BLE footpedal's keys
          arrive on kernels that drop its reports.

          ## The problem

          The pedal (BT HID-over-GATT -> uhid, `0005:0214:0002`) sends its
          boot-keyboard input report as **7 bytes** while its Report Map
          declares **8**. HID-core removed the legacy zero-padding of short
          reports in v7.0 (`0a3fe972a7cb`); uhid (all BLE HID devices) still
          dropped them through v7.1.3 -- dmesg shows `Event data for report
          0 was too short (8 vs 7)` and no key ever reaches evdev. Fixed
          upstream in v7.1.4+/v7.2 (`cfc0d283d931` / `63a694c51bf1`); full
          archaeology: `design/blueturn/kernel-uhid-shortreport.general.md`.

          ## The fix here

          `blueturn.bpf.c` is a HID-BPF `device_event` program that pads
          7->8 with a trailing zero -- byte-identical semantics to the old
          kernel padding. `udev-hid-bpf install` drops the compiled object
          in `/etc/udev-hid-bpf/` with a udev rule so it auto-attaches to
          **every** new uhid instance (the pedal churns instances on each
          BLE reconnect; manual per-device attach is whack-a-mole).

          ## Building

          `bin/build.sh` compiles against the RUNNING kernel: vmlinux.h is
          regenerated from `/sys/kernel/btf/vmlinux` (struct_ops layout must
          match exactly), conflicting kernel-BTF kfunc declarations are
          stripped against the installed libbpf, headers come from the
          udev-hid-bpf checkout (`udev-hid-bpf.src.pb` ->
          /usr/local/src/udev-hid-bpf-git, or
          ~/archive/libevdev/udev-hid-bpf).

          **After a kernel change, re-run `bin/install.sh`** (it rebuilds
          against the new BTF). Boot-time attach is automatic.

          Two hard-won specifics live in the source comments: struct_ops
          programs REQUIRE a GPL license section (missing = EINVAL on
          load), and the header conflict-strip loop exists because
          kernel-BTF vmlinux.h drifts ahead of Debian's libbpf.

          ## Watchers (diagnostics)

          - `bin/watch-blueturn.sh` -- live key events; default watches
            kanata's uinput outputs (what the compositor/wev receive).
            `raw` mode pauses kanata-blueturn and shows the pedal's true
            keycodes (reveals pedal mode + whether the BLE bearer was
            alive when you pressed).
          - `bin/watch-btmon.sh` -- HCI-level connect/disconnect trace
            with reason codes; the instrument for bearer-death forensics.

          ## Related

          - `kanata-blueturn.srv.pb` -- the pedal's kanata instance
          - `bluetooth-justworkrepair.etc.pb` -- BlueZ bonding repair
          - `kernel-usb-autosuspend.etc.pb` -- usb runtime suspend off
            (the adapter never sleeps)
          - `design/blueturn/` -- research + kernel archaeology
  tasks:
    - import_tasks: tasks/compfuzor.includes
