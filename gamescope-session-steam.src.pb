---
- hosts: all
  vars:
    TYPE: gamescope-session-steam
    INSTANCE: git
    REPO: https://github.com/ChimeraOS/gamescope-session-steam
    BINS:
      - name: install.sh
        exec: |
          #cp $(pwd)/usr/share/application/
  tasks:
    - include: tasks/compfuzor.includes type=src


