---
- hosts: all
  vars:
    TYPE: upplay
    INSTANCE: unstable
    APT_REPO: "http://www.lesbonscomptes.com/upmpdcli/downloads/debian-jessie/"
    APT_DISTRIBUTION: "{{INSTANCE}}"
    PKGS:
    - upplay
  tasks:
  - include: tasks/compfuzor.includes type=pkg
