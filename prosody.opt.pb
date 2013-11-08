---
- hosts: all
  gather_facts: False
  vars:
    NAME: prosody
    APT_REPO: http://packages.prosody.im/debian
    REPONAME: "{{NAME}}.unstable"
  tasks:
  - include: tasks/compfuzor.includes
  - include: tasks/apt.key.install.tasks name={{NAME}}
  - include: tasks/apt.list.install.tasks name={{REPONAME}}
  #- include: tasks/apt.srclist.install.tasks name={{REPONAME}}
  - apt: state={{APT_INSTALL}} pkg=prosody-trunk
