---
# via https://gist.github.com/kabili207/2cd2d637e5c7617411a666d8d7e97101
- hosts: all
  vars:
    TYPE: rclone
    INSTANCE: main
    ETC_DIRS: True
    SYSTEMD_SERVICES:
      ExecStart: "rclone mount --vfs-cache-mode writes --vfs-cache-max-size 100M --log-level=INFO --umask 022 --allow-other %i: %h/mnt/%i"
      ExecStop: fusermount -u %h/mnt/%i
    SYSTEMD_UNITS:
      After: "network-online.target"
      Description: rclone %i
    SYSTEMD_INSTALLS:
      Wants: "network-online.target"
    SYSTEMD_INSTANCES: True
    SYSTEMD_INSTALL: both
  tasks:
    - import_tasks: tasks/compfuzor.includes
