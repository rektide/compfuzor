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
    FILES_D:
    - /etc/locale.gen
  tasks:
  - include: tasks/compfuzor.includes
  - shell: locale-gen
  - file: path=/etc/locale.gen mode=644
