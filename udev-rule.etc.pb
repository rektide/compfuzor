---
- hosts: all
  vars:
    TYPE: udev-rule
    INSTANCE: main
    ETC_FILES:
      - destTemplate: '80-{{NAME}}.rules'
        src: rules
    LINKS:
      - srcTemplate: "{{ETC}}/80-{{NAME}}.rules"
        destTemplate: "/etc/udev/rules.d/80-{{NAME}}.rules"
    devices:
      - manufacturer: Razer
        set:
          "power/control": "on"
      - manufacturer: Kinesis
        set:
          "power/control": "on"
  tasks:
    - include: tasks/compfuzor.includes
