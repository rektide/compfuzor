---
- hosts: all
  vars:
    TYPE: bridge
    INSTANCE: main
    NAME: "br{{INSTANCE}}"
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
        Bridge={{NAME}}
    LINKS:
      "/etc/systemd/network/{{NAME}}.netdev": "{{ETC}}/{{NAME}}.netdev",
      "/etc/systemd/network/{{NAME}}.network": "{{ETC}}/{{NAME}}.network"
    devices:
    - en*

  tasks:
  - include: tasks/compfuzor.includes type=srv
