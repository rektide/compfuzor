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
    SYSTEMD_SERVICE: True
  vars_files:
  - ["private/nginx/$configset.vars", "private/nginx.vars", "examples-private/nginx.conf"]
  tasks:
  - include: tasks/compfuzor.includes type=srv
  - template: src=files/nginx/global.conf dest={{ETC}}/global.d/01-global.conf
  - file: src=/etc/nginx/mime.types dest={{ETC}}/mime.types state=link
