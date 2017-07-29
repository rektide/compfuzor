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
      partition_efi: 1
      partition_bios: 2
      partition_linux: 3
      dir_boot: "$var/linux/bios" # let shell interpolate var
      dir_efi: "$var/efi"
      label_linux: "{{label_linux|default('LinuxFlash')}}"
    BINS:
    - name: gpt.sh
    - name: install.sh
    - name: mnt.sh
    - name: unmount.sh
  tasks:
  - include: tasks/compfuzor.includes type=opt
