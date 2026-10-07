---
- hosts: all
  vars:
    TYPE: kernel-usb-autosuspend
    INSTANCE: main
    SYSTEMD_SERVICE: True
    SYSTEMD_SERVICES:
      Type: oneshot
      ExecStart: "{{DIR}}/bin/setup.sh"
      RemainAfterExit: true
    BINS:
      - name: setup.sh
        content: |
          # policy: USB runtime PM stays OFF on this box. BLE HID bearer
          # deaths (Surface Dial, iRig BlueTurn), daily xhci
          # invalid-context resets of the BT dongle under suspend churn,
          # and a historically slow-to-wake keyboard all trace to runtime
          # suspend; wake-from-device is only reliable on an awake device.
          # usbcore is built in, so modprobe.d cannot set its param --
          # this oneshot applies it every boot.
          echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend || true
          # btusb force-enables autosuspend in probe unless the module
          # param says otherwise; flip it live too (param stays rw).
          echo N | sudo tee /sys/module/btusb/parameters/enable_autosuspend 2>/dev/null || true
          # best-effort: pin every device's control to on; catches drivers
          # that force control=auto with their own delay. nothing here may
          # fail the oneshot.
          ( find -L /sys/bus/usb/devices -maxdepth 3 -path "*/power/control" -print0 |
          while IFS= read -r -d '' usb
          do
            echo on | sudo tee "$usb" >/dev/null 2>&1 || true
          done ) || true
          exit 0
    # history: the 2026-10 audit found the previous always-on rule was
    # triply dead -- doubled-backslash continuations failed udev parsing
    # outright (udevadm: Invalid key), it matched interface nodes, and usb
    # interfaces carry no power/ runtime-PM files at all. the writable
    # knobs live on the usb_device. before that fix the UB500 (sole btusb
    # adapter, hosts Dial + BlueTurn) had ~24 days runtime-suspended with
    # daily xhci resets.
    ETC_FILES:
      - name: usb-autosuspend.conf
        content: |
          # USB devices never runtime-suspend on this box.
          options usbcore autosuspend=-1
          # btusb opts itself back into autosuspend in probe unless told
          # not to -- the adapter hosting the Dial/BlueTurn never sleeps.
          options btusb enable_autosuspend=0
      - name: usb-always-on.rules
        content: |
          # belt for the boot-time hammer in setup.sh: hotplugged devices
          # pin awake too. device-level on purpose -- usb interfaces carry
          # no power/ runtime-PM files, and the prior interface-level rule
          # wrote ATTRs that never existed.
          ACTION=="add|bind", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", \
            ATTR{power/control}="on"
    LINKS:
      - src: "{{ETC}}/usb-autosuspend.conf"
        dest: "/etc/modprobe.d/usb-autosuspend.conf"
      - src: "{{ETC}}/usb-always-on.rules"
        dest: "/etc/udev/rules.d/90-usb-always-on.rules"
  tasks:
    - import_tasks: tasks/compfuzor.includes
