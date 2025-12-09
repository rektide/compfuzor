---
- hosts: all
  vars:
    TYPE: depot-tools
    INSTANCE: git
    REPO: https://chromium.googlesource.com/chromium/tools/depot_tools.git
    REPO_LINK_DIR: repo-link
    BINS:
      - name: use.sh
        content: |
          export PATH=\"$DIR:$PATH\"
          echo export PATH=\"$DIR:$PATH\"
  tasks:
    - import_tasks: tasks/compfuzor.includes
