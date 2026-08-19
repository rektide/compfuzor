---
- hosts: all
  gather_facts: False
  vars:
    NAME: xdg-dirs
    DIR: "{{ '/etc/xdg' if not USERMODE|default(False) else '~/.config' }}"
    ENV: "{{XDG}}"
    LINKS:
      - src: env
        dest: user-dirs.defaults
  tasks:
  - import_tasks: tasks/compfuzor.includes
