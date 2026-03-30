---
- hosts: all
  gather_facts: False
  vars:
    NAME: xdg-dirs
    DIR: "{{ '/etc/xdg' if not USERMODE|default(False) else '~/.config' }}"
    ENV: "{{XDG}}"
    LINKS:
      'user-dirs.defaults': 'env'
  tasks:
  #- import_tasks: tasks/compfuzor.includes
  - import_tasks: tasks/compfuzor/vars_env.tasks
  - file: path="{{DIR}}/user-dirs.defaults" state=absent
  - import_tasks: tasks/compfuzor/fs_env.tasks
  - import_tasks: tasks/compfuzor/links.tasks
