---
# via https://gist.github.com/kabili207/2cd2d637e5c7617411a666d8d7e97101
- hosts: all
  vars:
    target: "{{ '%h' if USERMODE|def else '' }}/mnt/%i'"
    SYSTEMD_SERVICES:
      # AH! This is the gotcha. User and service probably need different values here!
      # We'd started having two units, one for service & one for user. And would have USERMODE set when generating the users, so we could bifurcate this
      ExecStart: "rclone mount --vfs-cache-mode writes --vfs-cache-max-size 100M --log-level=INFO --umask 022 --allow-other %i: {{target}}"
      ExecStop: fusermount -u %h/mnt/%i
    SYSTEMD_UNITS:
      After: "network-online.target"
      Description: rclone %i
    SYSTEMD_INSTALLS:
      Wants: "network-online.target"
    SYSTEMD_INSTANCES: True
    SYSTEMD_INSTALL: separate
  tasks:
    - import_tasks: tasks/compfuzor.includes
