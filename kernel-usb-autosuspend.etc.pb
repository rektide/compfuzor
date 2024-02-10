---
- hosts: all
  vars:
    TYPE: kernel-usb-autosuspend
    INSTANCE: main
    ETC_FILES:
      - name: usb-autosuspend.conf
        content: |
          options usbcore autosuspend=900
    LINKS:
      - src: "{{ETC}}/usb-autosuspend.conf"
        dest: "/etc/modprobe.d/usb-autosuspend.conf"
  tasks:
    - include: tasks/compfuzor.includes
