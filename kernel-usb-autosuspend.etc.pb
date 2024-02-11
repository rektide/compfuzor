---
- hosts: all
  vars:
    TYPE: kernel-usb-autosuspend
    INSTANCE: main
    SYSTEMD_SERVICE: True
    SYSTEMD_TYPE: oneshot
    SYSTEMD_EXEC: "{{DIR}}/bin/setup.sh"
    BINS:
      - name: setup.sh
        content: |
          echo $AUTOSUSPEND | sudo tee /sys/module/usbcore/parameters/autosuspend
          find -L /sys/bus/usb/devices -maxdepth 3 -name "autosuspend_delay_ms" -print0 |
          while IFS= read -r -d '' usb
          do
            echo $usb
            echo $AUTOSUSPEND | sudo tee $usb >/dev/null
          done
    ETC_FILES:
      - name: usb-autosuspend.conf
        content: |
          options usbcore autosuspend={{autosuspend}}
    LINKS:
      - src: "{{ETC}}/usb-autosuspend.conf"
        dest: "/etc/modprobe.d/usb-autosuspend.conf"
    ENV:
      - autosuspend
    autosuspend: 900
  tasks:
    - include: tasks/compfuzor.includes type=etc
