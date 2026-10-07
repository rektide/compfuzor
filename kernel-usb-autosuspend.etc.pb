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
          # or in-use interfaces); nothing here may fail the oneshot.
          # per-device delays are MILLISECONDS while usbcore's autosuspend
          # param above is SECONDS -- the original loop wrote the seconds
          # value into the ms files, silently giving most devices a 0.9s
          # delay while rejecting devices kept the 15 min default.
          # btusb adapters are skipped here: udev owns their idle delays
          # (btusb-idle.rules -- 14 min blanket, 2 h override for the
          # adapter hosting the Surface Dial + BlueTurn).
          ( find -L /sys/bus/usb/devices -maxdepth 3 -name "autosuspend_delay_ms" -print0 |
          while IFS= read -r -d '' usb
          do
            dev="${usb%/power/autosuspend_delay_ms}"
            if ls -l "$dev"/*/driver 2>/dev/null | grep -q 'drivers/btusb$'
            then
              echo "skip btusb adapter: $dev"
              continue
            fi
            echo "$usb -> $AUTOSUSPEND_MS"
            echo $AUTOSUSPEND_MS | sudo tee "$usb" >/dev/null 2>&1 || true
          done ) || true
          exit 0
    # btusb runtime PM shapes bearer life for every BLE HID device (Surface
    # Dial, iRig BlueTurn): a suspended adapter silently kills LE bearers
    # minutes into a session, and suspend/resume churn on the UB500 dongle
    # showed up as daily xhci "invalid context state" resets. The 2026-10
    # audit found the previous always-on rule was triply dead: its "\\"
    # line continuations failed udev parsing outright (udevadm: Invalid key
    # '\ATTR'), it matched interface nodes, and usb interfaces carry no
    # power/ runtime-PM files -- the writable knobs live on the parent
    # usb_device, reached via ../ from the btusb interface bind event.
    ETC_FILES:
      - name: usb-autosuspend.conf
        content: |
          options usbcore autosuspend={{autosuspend}}
          # Escape hatch: keep every btusb adapter awake unconditionally by
          # opting btusb out of runtime PM entirely (module default is Y,
          # which lets btusb enable autosuspend; the udev delays above then
          # shape the idle window instead). Uncomment if delay-shaped
          # suspend still kills bearers (symptoms: ~10 min ATT death,
          # daily xhci invalid-context resets of the dongle):
          #options btusb enable_autosuspend=0
      - name: btusb-idle.rules
        content: |
          # idle delays before a btusb adapter may runtime-suspend. rules run
          # on the btusb interface add/bind event and write the PARENT
          # usb_device's power knobs -- interfaces have none of their own.
          # blanket: any btusb adapter idles {{bt_autosuspend}}s first
          ACTION=="add|bind", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", DRIVER=="btusb", \
            ATTR{../power/autosuspend_delay_ms}="{{bt_autosuspend * 1000}}"
          # override: the UB500 dongle (2357:0604) hosts the Surface Dial +
          # iRig BlueTurn; 2 h idle so long sessions never see the adapter
          # sleep. Listed after the blanket rule, so on the same event its
          # write lands last and wins.
          ACTION=="add|bind", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", DRIVER=="btusb", \
            ATTRS{idVendor}=="2357", ATTRS{idProduct}=="0604", \
            ATTR{../power/autosuspend_delay_ms}="{{bt_override_autosuspend * 1000}}"
    LINKS:
      - src: "{{ETC}}/usb-autosuspend.conf"
        dest: "/etc/modprobe.d/usb-autosuspend.conf"
      - src: "{{ETC}}/btusb-idle.rules"
        dest: "/etc/udev/rules.d/90-btusb-idle.rules"
    ENV:
      AUTOSUSPEND: "{{autosuspend}}"
      AUTOSUSPEND_MS: "{{autosuspend * 1000}}"
    autosuspend: 900               # seconds; global usbcore idle delay
    bt_autosuspend: 840            # seconds; blanket btusb adapter idle (14 min)
    bt_override_autosuspend: 7200  # seconds; UB500 (Dial + BlueTurn) idle (2 h)
  tasks:
    - import_tasks: tasks/compfuzor.includes
