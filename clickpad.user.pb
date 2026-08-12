---
- hosts: all
  gather_facts: False
  vars:
    NAME: clickpad
    USERMODE: True
    ETC_FILES:
    - clickpad.xinitrc
    FILES:
      - name: .xinitrc.d/foo
        src: clickpad.xinitrc
    DIRS:
      - .xinitrc.d
    CONFIGS:
      .xinitrc:
        dir: "{{home.stdout}}"
        name: clickpad
        processor: concat
        disabled_suffix: false
        inputs:
          - glob: .xinitrc.d/*
  tasks:
  - shell: echo $HOME
    register: home
  - include: tasks/compfuzor.includes
