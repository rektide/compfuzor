---
- hosts: all
  vars:
    TYPE: gmusicproxy
    INSTANCE: main
    ETC_FILES:
    - gmusicproxy.cfg
    LOG_DIR: True
    LINKS:
      "{{ETCS_DIR}}/gmusicproxy.cfg": "{{ETC}}/gmusicproxy.cfg"
    SYSTEMD_EXEC: "{{gmusicproxy_dir}}/gmusicproxy"
    email: "{{ ansible_user_id }}@gmail.com"
    password: HAHAHA_WHAT
    gmusicproxy_dir: /usr/local/bin
    port: 9999
  tasks:
  - include: tasks/compfuzor/vars_base.tasks type=srv
  - stat: path="{{GLOBAL_BINS_DIR}}/gmusicproxy"
    register: has_gmusicproxy
  - set_fact:
      gmusicproxy_dir: "{{GLOBAL_BINS_DIR|replace('~', '%h')}}"
    when: has_gmusicproxy.stat.exists
  - include: tasks/compfuzor.includes type=srv
