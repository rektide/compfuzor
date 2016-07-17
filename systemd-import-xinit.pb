---
- hosts: all
  vars:
    TYPE: xinit-systemd-user
  tasks:
  - copy: src=files/systemd-import-xinit/50-systemd-import.sh dest=/etc/X11/xinit/xinitrc.d/50-systemd-import.sh
