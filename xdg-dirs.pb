---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.user.vars
  - vars/xdg.vars
  vars:
    NAME: xdg-dirs
    DIR: {{ '/etc/xdg' if not USERMODE|default(False) else '~/.config'
    ENV: "{{XDG}}"
    LINKS:
      'user-dirs.defaults': 'env'
  tasks:
  #- include: tasks/compfuzor.includes
  - include: tasks/compfuzor/vars_env.tasks
  - file: path="{{DIR}}/user-dirs.defaults" state=absent
  - include: tasks/compfuzor/fs_env.tasks
  - include: tasks/compfuzor/links.tasks
