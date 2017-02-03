---
- hosts: all
  vars:
    TYPE: bridge
    INSTANCE: main
    ETC_FILES:
    - name: "{{NAME}}.netdev"
      content: |
        [NetDev]
        Name={{NAME}}
        Kind=bridge
    - name: "{{NAME}}.network"
      content: |
        [Match]
        Name={{devices|join(" ")}}
        [Network]
        Bridge=brmain
    devices:
    - en*
  tasks:
  - include: tasks/compfuzor.includes type=srv
