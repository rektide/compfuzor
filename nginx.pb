---
- hosts: all
  gather_facts: False
  vars:
    TYPE: nginx
    INSTANCE: main
    packages:
    - nginx-extras
    - nginx-common
    - nginx-doc
    ETC_DIRS:
    - global.d
    - hosts.d
    ETC_FILES:
    - nginx.conf
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  - ["private/nginx/$configset.vars", "private/nginx.vars", "examples-private/nginx.conf"]
  tasks:
  - include: tasks/cfvar_includes.tasks
  - apt: pkg=$packages state=${APT_INSTALL}
    with_items: $packages
  - template: src=files/nginx/global.conf dest={{ETC.stdout}}/global.d/01-global.conf
  - template: src=files/nginx/nginx.conf dest={{ETC.stdout}}/nginx.conf
  - template: src=files/nginx/nginx.service dest={{SYSTEMD_SERVICE.stdout}}
  - file: src=/etc/nginx/mime.types dest={{ETC.stdout}}/mime.types state=link
  - include: tasks/systemctl.thunk.service
