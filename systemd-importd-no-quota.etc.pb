---
- hosts: all
  vars:
    TYPE: systemd-importd-no-quota
    INSTANCE: main
    ETC_FILES:
      - name: systemd-importd-no-quota.conf
        content: |
          [Service]
          Environment=SYSTEMD_IMPORT_BTRFS_QUOTA=0
    BINS:
      - name: install.sh
        content: |
          set -e
          sudo mkdir -p /etc/systemd/system/systemd-importd.service.d
          sudo ln -sf {{ETC}}/systemd-importd-no-quota.conf /etc/systemd/system/systemd-importd.service.d/systemd-importd-no-quota.conf
          sudo systemctl daemon-reload
  tasks:
    - import_tasks: tasks/compfuzor.includes
