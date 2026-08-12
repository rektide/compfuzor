---
- hosts: all
  gather_facts: False
  vars:
    NAME: clickpad
    USERMODE: True
    ETC_FILES:
    - clickpad.xinitrc
    DROPINS:
      clickpad:
        root: "{{home.stdout}}"
        path: .xinitrc.d
        include: "*"
        files:
        - name: foo
          src: clickpad.xinitrc
    CONFIGS:
      clickpad:
        root: "{{home.stdout}}"
        assemblies:
          main:
            output: .xinitrc
            processor: concat
            inputs:
            - dropins: clickpad
  tasks:
  - shell: echo $HOME
    register: home
  - include: tasks/compfuzor.includes
