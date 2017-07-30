---
- hosts: all
  vars:
    TYPE: grub-hybrid
    INSTANCE: main
    VAR_DIRS:
    - efi
    - linux
    ENV:
      var: "{{VAR}}"
      partition_efi: "${DEV}1"
      partition_bios: "${DEV}2"
      partition_linux: "${DEV}3"
      dir_boot: "$VAR/linux/bios" # let shell interpolate var
      dir_efi: "$VAR/efi"
      label_linux: "{{label_linux|default('LinuxFlash')}}"
    BINS:
    - name: gpt.sh
    - name: install.sh
    - name: mnt.sh
    - name: unmount.sh
  tasks:
  - include: tasks/compfuzor.includes type=opt
