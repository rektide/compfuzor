---
- hosts: all
  vars:
    NAME: systemd-import-xsession
    ETC_FILES:
    - 96systemd-import
    LINKS:
      "{{ETC}}/96systemd-import": "/etc/X11/Xsession.d/96systemd-import"
  tasks:
  - include: tasks/compfuzor.includes type=etc
