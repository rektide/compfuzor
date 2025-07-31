---
# useful on steam deck where base repo is not present
- hosts: all
  vars:
    TYPE: pacman-repo
    INSTANCE: main
    ETC_FILES:
      - name: pacman.list
        content: |
          {% for server in servers %}
          Server = {{server}}
          {% endfor %}
      - name: pacman.conf
        content: |
          {% for section in sections %}
          [{{section}}]
          Include = /etc/pacman.d/{{NAME}}.list
          {% endfor %}
    LINKS:
      - src: "{{ETC}}/pacman.list"
        dest: "/etc/pacman.d/{{NAME}}.list"
    servers:
      - https://mirror.colonelhosting.com/archlinux/$repo/os/$arch
      - https://mirror.umd.edu/archlinux/$repo/os/$arch
      - https://mirror.mra.sh/archlinux/$repo/os/$arch
      - https://arch.mirror.constant.com/$repo/os/$arch
      - https://iad.mirrors.misaka.one/archlinux/$repo/os/$arch
      - https://mirror.pilotfiber.com/archlinux/$repo/os/$arch
      - https://mirror.zackmyers.io/archlinux/$repo/os/$arch
    sections:
      - core
      - extra
      #- community
    BINS:
      - name: install.sh
        content: |
          sudo chgrp wheel /etc/pacman.conf
          block-in-file -n ${NAME:-{{NAME}}} -i etc/pacman.conf /etc/pacman.conf
  tasks:
    - import_tasks: tasks/compfuzor.includes
