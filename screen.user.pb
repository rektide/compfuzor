---
- hosts: all
  gather_facts: False
  vars:
    NAME: screen
    DIR: "~"
    ETC: "{{HOMEDIR}}/.screenrc.d"
    ETC_FILES:
    - "utf8"
    DROPINS:
      screen:
        root: "{{HOMEDIR}}"
        path: .screenrc.d
        include: "*"
    CONFIGS:
      screen:
        root: "{{HOMEDIR}}"
        assemblies:
          main:
            output: .screenrc
            processor: concat
            inputs:
            - dropins: screen
  tasks:
  - include: tasks/compfuzor.includes
