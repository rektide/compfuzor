---
- hosts: all
  gather_facts: False
  vars:
    alternatives:
      x-window-manager: "/usr/bin/awesome"
      x-terminal-emulator: "/usr/bin/terminator"
  tasks:
  - shell: update-alternatives --set "{{ item.key }}" "{{ item.value }}"
    with_dict: alternatives
