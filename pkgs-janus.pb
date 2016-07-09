---
# http://projects.ag-projects.com/projects/documentation/wiki/Repositories
- hosts: all
  vars:
    TYPE: janus
    INSTANCE: deb
    APT_REPO: http://ag-projects.com/debian
    APT_DISTRO: unstable
  tasks:
  - include: tasks/compfuzor.includes type="pkg"
