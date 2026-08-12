---
- hosts: all
  gather_facts: False
  vars:
    TYPE: locales
    INSTANCE: utf8
    DIR: /etc/locale.gen.d
    FILES:
    - 00-INDEX
    - utf8
    CONFIGS:
      locale.gen:
        dir: /etc
        processor: concat
        disabled_suffix: false
        inputs:
          - glob: locale.gen.d/*
  tasks:
  - include: tasks/compfuzor.includes
  - shell: locale-gen
  - file: path=/etc/locale.gen mode=644
