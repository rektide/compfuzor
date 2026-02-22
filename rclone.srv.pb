---
# via https://gist.github.com/kabili207/2cd2d637e5c7617411a666d8d7e97101
- hosts: all
  vars:
    TYPE: rclone
    ETC_DIRS: True
    INSTANCE: main
    SYSTEMD_SERVICE: rclone
    SYSTEMD_EXEC: "rclone mount --vfs-cache-mode writes --vfs-cache-max-size 100M --log-level=INFO --umask 022 --allow-other %i: %h/mnt/%i"
    SYSTEMD_EXEC_STOP: fusermount -u %h/mnt/%i
    SYSTEMD_AFTER: "network-online.target"
    SYSTEMD_WANTS: "network-online.target"
    SYSTEMD_DESCRIPTION: rclone %i
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTANCES: True
    SYSTEMD_USERMODE: "{{USERMODE|default(False)}}"
    SYSTEMD_DEST: "{{USERMODE|ternary(SYSTEMD_USER_UNIT_DIR, omit)}}"
  tasks:
    - include: tasks/compfuzor.includes type=srv
