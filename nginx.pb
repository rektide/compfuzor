---
# http://blog.zachorr.com/nginx-setup/
- hosts: all
  vars:
    TYPE: nginx
    INSTANCE: main
    PKGS:
    - nginx-extras
    - nginx-common
    - nginx-doc
    ETC_DIRS:
    - global.d
    - hosts.d
    - conf.d
    ETC_FILES:
    - nginx.conf
    LOG_DIRS: true
    SYSTEMD_EXEC: "/usr/sbin/nginx -c {{ETC}}/nginx.conf"
    SYSTEMD_EXEC_START_PRE: "/usr/sbin/nginx -c {{ETC}}/nginx.conf -t"
    SYSTEMD_RELOAD: "/bin/kill -s HUP $MAINPID"
    SYSTEMD_EXEC_STOP: "/bin/kill -s QUIT $MAINPID"
    SYSTEMD_PRIVATE_TMP: True
    SYSTEMD_PID_FILE: "{{PID}}.pid"
    SYSTEMD_USER: "root"
  vars_files:
  - ["private/nginx/$configset.yaml", "private/nginx.yaml", "examples-private/nginx.yaml"]
  tasks:
  - include: tasks/compfuzor.includes type=srv
  - template: src=files/nginx/global.conf dest={{ETC}}/global.d/01-global.conf
  - file: src=/etc/nginx/mime.types dest={{ETC}}/mime.types state=link
