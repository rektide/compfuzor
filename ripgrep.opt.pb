---
- hosts: all
  vars:
    TYPE: ripgrep
    INSTANCE: main
    version: 0.8.1
    GET_URLS: "https://github.com/BurntSushi/ripgrep/releases/download/{{version}}/ripgrep_{{version}}_amd64.deb"
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - apt:
      deb: "{{SRC}}/{{GET_URLS|basename}}"
    become: True
