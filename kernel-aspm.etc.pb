---
- hosts: all
  vars:
    TYPE: kernel-aspm
    INSTANCE: main
    SYSTEMD_SERVICE: True
    SYSTEMD_TYPE: oneshot
    SYSTEMD_EXEC: "{{DIR}}/bin/setup.sh"
    BINS:
      - name: setup.sh
        content: echo $POLICY | sudo tee /sys/module/pcie_aspm/parameters/policy
    ETC_FILES:
      - name: kernel-aspm.conf
        content: |
          options pcie_aspm policy=superpowersave
    LINKS:
      - src: "{{ETC}}/kernel-aspm.conf"
        dest: "/etc/modprobe.d/kernel-aspm.conf"
    ENV:
      - policy
    policy: powersupersave
  tasks:
    - include: tasks/compfuzor.includes type=etc
