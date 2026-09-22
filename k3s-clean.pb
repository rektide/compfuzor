---
# Teardown for compfuzor-deployed k3s (server or agent instances).
#
# Removes the instance dirs/unit plus the system state k3s leaves outside the
# data dir (kubelet, CNI, run dirs, kube/cni iptables), mirroring the
# relevant parts of upstream k3s-uninstall.sh WITHOUT removing the k3s
# binary or anything compfuzor owns separately. Identity choice is yours:
#   - keep /etc/opt/<NAME> (secrets/token) -> a later redeploy + snapshot
#     restore keeps the same cluster identity (token match is REQUIRED for
#     restore; the snapshot encryption key derives from it)
#   - force_clean=True wipes etc too       -> scorched earth, fresh cluster
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
    # k3s system state outside the data dir (upstream k3s-uninstall.sh
    # territory: a data-dir-only delete leaves all of this behind). Applies
    # to agents too -- kubelet and CNI state exist on both.
    system_state_paths:
      - /var/lib/kubelet
      - /var/lib/cni
      - /run/k3s
      - /run/flannel
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
  - import_tasks: tasks/compfuzor/vars_base.tasks
  - import_tasks: tasks/compfuzor/vars_hierarchy.tasks
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
  - name: umount kubelet/cni runtime mounts (rm -rf fails on these)
    ansible.builtin.shell: |
      mount | awk '/\/var\/lib\/kubelet|\/run\/k3s|\/run\/netns\/cni/ {print $3}' | xargs -r -n1 umount -f || true
    args:
      executable: /bin/sh
    become: true
  - name: delete files
    ansible.builtin.file:
      path: "{{item}}"
      state: absent
    become: true
    when: item != ""
    loop: "{{paths}}"
  - name: delete k3s system state (kubelet, cni, run dirs)
    ansible.builtin.file:
      path: "{{item}}"
      state: absent
    become: true
    loop: "{{system_state_paths}}"
  - name: scrub cni interfaces and kube/cni/flannel iptables
    ansible.builtin.shell: |
      for i in cni0 flannel.1 flannel-v6.1 kube-ipvs0 flannel-wg flannel-wg-v6; do
        ip link del "$i" 2>/dev/null || true
      done
      for tbl in iptables ip6tables; do
        if command -v "$tbl-save" >/dev/null 2>&1; then
          "$tbl-save" | grep -v -e 'KUBE-' -e 'CNI-' -e 'flannel' | "$tbl-restore" || true
        fi
      done
    args:
      executable: /bin/sh
    become: true
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
