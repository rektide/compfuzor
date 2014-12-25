---
- hosts: all
  vars:
    TYPE: synergy
    INSTANCE: main
    USERMODE: True
    PKGS:
    - synergy
    ETC_FILES:
    - synergy.json
    - src: "../_empty"
      dest: synergy.conf
    VAR_FILES:
    - name: synergy.conf.j2
      raw: True
    SYSTEMD_SERVICE: True
    SYSTEMD_EXEC: "/usr/bin/synergys -f -d INFO"
    BINS:
    - name: build-etc
      run: True
      global: False
    LINKS:
      "~/.synergy.conf": "{{ETC}}/synergy.conf"
  tasks:
  - include: tasks/compfuzor.includes type=opt
