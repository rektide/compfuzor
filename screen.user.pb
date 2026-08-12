---
- hosts: all
  gather_facts: False
  vars:
    NAME: screen
    DIR: "~"
    ETC: "{{HOMEDIR}}/.screenrc.d"
    ETC_FILES:
    - "utf8"
    CONFIGS:
      .screenrc:
        dir: "{{HOMEDIR}}"
        name: screen
        processor: concat
        disabled_suffix: false
        inputs:
          - glob: .screenrc.d/*
  tasks:
  - include: tasks/compfuzor.includes
