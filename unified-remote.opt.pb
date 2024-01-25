---
- hosts: all
  vars:
    TYPE: urserver # unified-remote server
    version: 3.13.0.2505
    rev: "{{ version[-4:] }}"
    INSTANCE: "{{ version }}"
    arch: linux-x64
    prefix: "https://www.unifiedremote.com/static/builds/server/linux-x64/{{rev}}"
    DEB: "{{prefix}}/urserver-{{version}}.deb"
    TGZ: "{{prefix}}/urserver-{{version}}.tar.gz"
  tasks:
  - include: tasks/compfuzor.includes type=opt
