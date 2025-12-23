---
- hosts: all
  vars:
    REPO: https://github.com/hzeller/gmrender-resurrect
    ENV: True
    SYSTEMD_SERVICE: True
    SYSTEMD_SERVICES:
      ExecStart: "/usr/bin/gmediarender --logfile /dev/stdout"
    ETC_DIR: True
    BINS:
      - name: build.sh
        exec: |
          ./autogen.sh
          ./configure --with-gstreamer
          make
      - name: install.sh
        exec: |
          sudo make install
      - name: install-user.sh
        content: |
          ln -s $(pwd)/etc/{{NAME}}.service ~/.config/systemd/user/
  tasks:
    - import_tasks: tasks/compfuzor.includes
