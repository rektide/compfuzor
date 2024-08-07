---
- hosts: all
  vars_files:
    - vars/common.yaml
  vars:
    TYPE: "{{prefix}}{{ is_server|ternary('', '-agent') }}"
    INSTANCE: "{{server|replace('.', '-')}}"
    NAME: "{{TYPE}}-{{INSTANCE}}"
    prefix: "k3s"
    server: "k3s.example"

    force_clean: False
    is_server: "{{ 'servers' in group_names }}"
    paths:
      - "/srv/{{NAME}}"
      - "/var/lib/{{NAME}}"
      - "/etc/opt/{{NAME}}"
      - "{{SYSTEMD_SYSTEM_UNIT_DIR}}/{{NAME}}.service"
    # dest will be deleted if it points at src
    # or if force_clean
    global_links:
    - dest: "{{SYSTEMD_SYSTEM_UNIT_DIR}}/k3s.service"
      src:  "{{SYSTEMD_SYSTEM_UNIT_DIR}}/{{NAME}}.service"
    - dest: "/var/lib/rancher/k3s"
      src: "{{VAR}}/data"
    - dest: "/etc/rancher/k3s"
      src: "{{ETC}}"
    # currently not setup by k3s playbooks
    - dest: "/etc/rancher/node"
      src: "/dev/null"
  tasks:
  - include: tasks/compfuzor/vars_base.tasks
  - include: tasks/compfuzor/vars_hierarchy_multi.tasks
  - name: read k3s link
    stat:
      path: "{{item.dest}}"
    register: global_stat
    loop: "{{global_links}}"
  - name: stop services
    ansible.builtin.systemd:
      name: "{{NAME}}"
      state: stopped
    failed_when: False
    become: true
  - name: delete files
    ansible.builtin.file:
      path: "{{item}}"
      state: absent
    become: true
    when: item != ""
    loop: "{{paths}}"
  - name: delete global links
    ansible.builtin.file:
      path: "{{item.item.dest}}"
      state: absent
    when: force_clean|default(False) or item.stat.lnk_target|default('') == item.item.src or item.stat.lnk_source|default('') == item.item.src
    become: true
    loop: "{{global_stat.results}}"
  - name: systemd daeon-reload
    shell: "systemctl daemon-reload"
    become: true
