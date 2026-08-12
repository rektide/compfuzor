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
    DROPINS:
      locales:
        root: /etc
        path: locale.gen.d
        include: "*"
    CONFIGS:
      locales:
        root: /etc
        assemblies:
          main:
            output: locale.gen
            processor: concat
            inputs:
            - dropins: locales
  tasks:
  - include: tasks/compfuzor.includes
  - shell: locale-gen
  - file: path=/etc/locale.gen mode=644
