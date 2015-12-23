---
- hosts: all
  vars:
    TYPE: gmusicproxy
    INSTANCE: main
    ETC_FILES:
    - gmusicproxy.cfg
    LOG_DIR: True
    LINKS:
    - "{{ETCS_DIR}}/gmusicproxy.cfg":  "{{ETC}}/gmusicproxy.cfg"
    SYSTEMD_EXEC: "/usr/local/bin/gmusicproxy"
    email: "{{ ansible_user_id }}"
    password: HAHAHA_WHAT
  tasks:
  - include: tasks/compfuzor.includes type=srv
