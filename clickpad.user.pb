---
- hosts: all
  gather_facts: False
  vars:
    NAME: clickpad
    USERMODE: True
    ETC_FILES:
    - clickpad.xinitrc
    XINITRC: "{{home.stdout}}"
    XINITRC_D: 
    - ".xinitrc"
    LINKS_BYPASS: True
    LINKS:
      "{{home.stdout}}/.xinitrc.d/foo": "{{ETC}}/clickpad.xinitrc"
  tasks:
  - shell: echo $HOME
    register: home
  - include: tasks/compfuzor.includes
  - include: tasks/compfuzor/vars_hierarchy.tasks include=xinitrc
  - include: tasks/compfuzor/fs_hierarchy.tasks include=xinitrc
  - shell: "echo DIR {{DIR}} >> /tmp/FOO"
  - shell: "echo ETC {{ETC}} >> /tmp/FOO"
  - include: tasks/compfuzor/links.tasks
  - include: tasks/compfuzor/fs_d.tasks include=xinitrc
