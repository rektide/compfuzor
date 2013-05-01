---
- hosts: all
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
    - conf.d
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
  - template: src=files/nginx/global.conf dest={{ETC}}/global.d/01-global.conf
  - template: src=files/nginx/nginx.conf dest={{ETC}}/nginx.conf
  - file: src=/etc/nginx/mime.types dest={{ETC}}/mime.types state=link
  - include: tasks/systemd.service.tasks src=files/nginx/nginx.service service={{NAME}}
