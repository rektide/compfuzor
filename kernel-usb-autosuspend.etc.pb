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
          echo $AUTOSUSPEND | sudo tee /sys/module/usbcore/parameters/autosuspend || true
          # best-effort: some devices reject delay writes (e.g. PM QoS
          # or in-use interfaces); nothing here may fail the oneshot
          ( find -L /sys/bus/usb/devices -maxdepth 3 -name "autosuspend_delay_ms" -print0 |
          while IFS= read -r -d '' usb
          do
            echo $usb
            echo $AUTOSUSPEND | sudo tee $usb >/dev/null 2>&1 || true
          done ) || true
          exit 0
    # btusb adapters must never runtime-suspend: an autosuspended
    # adapter silently kills LE HID bearers minutes after connect (the
    # iRig BlueTurn died ~10min in; kernel-7.1+ drops made it look like
    # a pairing problem). udev re-arms control=on at every add/bind.
    ETC_FILES:
      - name: usb-autosuspend.conf
        content: |
          options usbcore autosuspend={{autosuspend}}
      - name: btusb-always-on.rules
        content: |
          # iRig BlueTurn bearer deaths (~10min after connect) traced to
          # btusb runtime PM; keep the adapter awake unconditionally.
          ACTION=="add|bind", SUBSYSTEM=="usb", DRIVER=="btusb", \\
          ATTR{power/control}="on", \\
          ATTR{power/autosuspend_delay_ms}="-1"
    LINKS:
      - src: "{{ETC}}/usb-autosuspend.conf"
        dest: "/etc/modprobe.d/usb-autosuspend.conf"
      - src: "{{ETC}}/btusb-always-on.rules"
        dest: "/etc/udev/rules.d/90-btusb-always-on.rules"
    ENV:
      AUTOSUSPEND: "{{autosuspend}}"
    autosuspend: 900
  tasks:
    - import_tasks: tasks/compfuzor.includes
