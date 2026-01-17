---
- hosts: all
  vars:
    INSTANCE: eno1
    ETC_FILES:
      - name: wol.link
        content: |
          [Match]
          OriginalName={{INSTANCE}}

          [Link]
          WakeOnLan=magic
    BIN:
      - name: install.sh
        content: |
          sudo ln -s {{ETC}}/wol.link /etc/systemd/network/wol-{{INSTANCE}}.link
  tasks:
    - import_tasks: tasks/compfuzor.includes
