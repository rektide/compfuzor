---
- hosts: all
  gather_facts: False
  vars:
    NAME: prosody
    APT_REPO: http://packages.prosody.im/debian
    REPONAME: "{{NAME}}-unstable"
    PKGS:
    - prosody-trunk
  tasks:
  - include: tasks/compfuzor.includes
