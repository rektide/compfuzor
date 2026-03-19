---
- hosts: all
  vars:
    SYSTEMD_SERVICES:
      ExecStart: lact daemon
  tasks:
    - import_tasks: tasks/compfuzor.includes
