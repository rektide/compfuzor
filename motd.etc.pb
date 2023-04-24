---
- hosts: all
  vars:
    TYPE: motd
    INSTANCE: main
    ETC_FILES:
      - name: motd
        content: "{{message}}"
    BINS:
      - name: install.sh
        become: True
        content: |
          sudo ln -s "{{ETC}}/motd" /etc/motd
    message: "welcome!"
  tasks:
    - include: tasks/compfuzor.includes type=etc
