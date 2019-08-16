---
- hosts: all
  vars:
    TYPE: rtl8814au
    INSTANCE: git
    REPO: https://github.com/tpircher/rtl8814AU
    BINS:
    - name: build.sh
      exec: |
        dkms build -m {{NAME}} -v {{KERNEL_RELEASE}}
        dkms install -m {{NAME}} -v {{KERNEL_RELEASE}}
    LINKS:
      "/usr/src/{{NAME}}": "{{DIR}}"
      "/usr/src/{{NAME}}-{{KERNEL_RELEASE}}": "/usr/src/{{NAME}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
