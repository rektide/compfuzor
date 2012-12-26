---
- hosts: all
  sudo: True
  vars:
    exec_user: root
    dest: /etc/autossh-tunnels
  vars_files:
  - vars/common.vars
  - private/autossh-tunnels/autossh_config.vars
  tasks:
  - apt: state=$APT_INSTALL pkg=autossh
  - file: state=directory owner=${exec_user} group=root mode=0600 path=${dest}
  - file: state=directory owner=${exec_user} group=root mode=0600 path=${dest}/keys
  - template: src=files/autossh-tunnels/autossh_config dest=${dest}/autossh_config
    register: has_config
  - template: src=files/autossh-tunnels/autossh-tunnels.service dest=/etc/systemd/system/autossh-tunnels-${item.host}.service
    with_items: $hosts
    register: has_service
  - copy: src=$item dest=${dest}/keys mode=0400
    with_fileglob: private/autossh-tunnels/keys/*
  - shell: systemctl enable autossh-tunnels-${item.host}.service
    with_items: $hosts
    only_if: ${has_service.changed} or ${has_config.changed}
  - shell: systemctl reload-or-restart autossh-tunnels-${item.host}.service
    with_items: $hosts
    only_if: ${has_service.changed} or ${has_config.changed}
