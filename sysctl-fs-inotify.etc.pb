---
- hosts: all
  vars:
    TYPE: fs-inotify
    SYSCTL:
      fs.inotify.max_user_watches: 1048576
      fs.inotify.max_user_instances: 8192
  tasks:
    - import_tasks: tasks/compfuzor.includes type=etc
