---
- hosts: all
  vars:
    TYPE: kernel-usb-autosuspend
    INSTANCE: main
    SYSTEMD_SERVICE: True
    SYSTEMD_SERVICES:
      Type: oneshot
      ExecStart: "{{DIR}}/bin/apply-devices.sh"
      RemainAfterExit: true
    PKGS:
      - fd-find
    KERNEL_MODULES:
      btusb:
        load: false
        params:
          # btusb opts itself back into runtime PM in probe unless told
          # not to -- the adapter hosting the Dial/BlueTurn never sleeps.
          enable_autosuspend: 0
    KERNEL_SYSFS:
      # usbcore is built in, so modprobe.d cannot reach it; the kernel
      # subsystem turns this into a tmpfiles.d entry applied at boot.
      # -1 = no usb device runtime-suspends by default.
      /sys/module/usbcore/parameters/autosuspend: "-1"
    BINS:
      - name: apply-devices.sh
        content: |
          # policy: USB runtime PM stays OFF on this box. BLE HID bearer
          # deaths (Surface Dial, iRig BlueTurn), daily xhci
          # invalid-context resets of the BT dongle under suspend churn,
          # and a historically slow-to-wake keyboard all trace to runtime
          # suspend; wake-from-device is only reliable on an awake device.
          # module params come from the kernel subsystem (modprobe.d via
          # KERNEL_MODULES, tmpfiles.d via KERNEL_SYSFS); this pins each
          # usb_device's control to on. depth-1 entries under devices/
          # are devices, hub-nested devices, and interfaces -- interfaces
          # carry no power/ runtime-PM files and are skipped by the
          # existence guard. best effort: nothing here may fail the
          # oneshot.
          ( fd -L -d 1 -0 --type d . /sys/bus/usb/devices |
          while IFS= read -r -d '' dev
          do
            usb="$dev/power/control"
            if [ -e "$usb" ]
            then
              echo "$usb -> on"
              echo on | sudo tee "$usb" >/dev/null 2>&1 || true
            fi
          done ) || true
          exit 0
    # history: the 2026-10 audit found the previous always-on rule was
    # triply dead -- doubled-backslash continuations failed udev parsing
    # outright (udevadm: Invalid key), it matched interface nodes, and usb
    # interfaces carry no power/ runtime-PM files at all. the writable
    # knobs live on the usb_device. before the fix the UB500 (sole btusb
    # adapter, hosts Dial + BlueTurn) had ~24 days runtime-suspended with
    # daily xhci resets.
    ETC_FILES:
      - name: usb-always-on.rules
        content: |
          # belt for the boot-time hammer in apply-devices.sh: hotplugged
          # devices pin awake too. device-level on purpose -- usb
          # interfaces carry no power/ runtime-PM files, and the prior
          # interface-level rule wrote ATTRs that never existed.
          ACTION=="add|bind", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", \
            ATTR{power/control}="on"
    LINKS:
      - src: "{{ETC}}/usb-always-on.rules"
        dest: "/etc/udev/rules.d/90-usb-always-on.rules"
  tasks:
    - import_tasks: tasks/compfuzor.includes
