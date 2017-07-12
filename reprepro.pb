---
# TODO: inoticoming to watch incoming
- hosts: all
  vars:
    TYPE: reprepro
    INSTANCE: main
    LOG_DIRS: true
    VAR_DIRS:
    - www/dists
    - www/pool
    - db
    - incoming
    - tmp/list
    - tmp/incoming
    DIRS:
    - .z
    ETC_FILES:
    - distributions
    - options
    - incoming
    LINKS:
      dists: var/www/dists
      pool: var/www/pool
      conf: etc
      .z/reprepro.env: env
    PKGS:
    - reprepro
    BINS:
    - build.sh
    GIT_BYPASS: True
    nginx_prio: 50
  vars_files:
  - [ "private/reprepro/$configset.yaml", "private/reprepro.yaml", "examples-private/reprepro.yaml" ]
  tasks:
  - include: tasks/compfuzor.includes type=srv
  - template: src=files/reprepro/override dest="{{ETC}}/override-dsc.{{item.name}}"
    with_items: REPREPROS
    when: item.overrides|default(False)
  - template: src=files/reprepro/override dest="{{ETC}}/override-deb.{{item.name}}"
    with_items: REPREPROS
    when: item.overrides|default(False)
  - file: path="{{VAR}}/incoming/{{item.name}}" state=directory
    with_items: REPREPROS
  - file: path="{{VAR}}/tmp/incoming/{{item.name}}" state=directory
    with_items: REPREPROS
  - file: path="{{VAR}}" group=www-data mode=710
  - file: path="{{VAR}}" group=www-data mode=750 recurse=true
  # TODO: private/ keys install
  - include: tasks/nginx-confs.tasks hosts={{REPREPROS}} nginx="{{NGINX_ETC}}" conf="files/reprepro/nginx.conf"
  #- include: tasks/systemd.alias.tasks src="{{NGINX}}" dest="{{NAME}}"
  - include: tasks/systemd.thunk.tasks service="{{NGINX}}"
