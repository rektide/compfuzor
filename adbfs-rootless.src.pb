---
- hosts: all
  vars:
    REPO: https://github.com/spion/adbfs-rootless
    ENV: True
    BINS:
      - name: build.sh
        content: make all
      - name: install.sh
        content: ln -sfv $(pwd)/adbfs $GLOBAL_BINS_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes
