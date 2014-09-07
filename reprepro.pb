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
      .z/reprepro.env: env
      conf: etc
    #VARS:
    #- reprepro
    GIT_BYPASS: True
    nginx_prio: 50
  vars_files:
  - [ "private/reprepro/$configset.vars", "private/reprepro.vars", "examples-private/reprepro.vars" ]
  gather_facts: false
  handlers:
  - include: handlers.yml
  tasks:
  - include: tasks/compfuzor.includes type=srv
  - template: src=files/reprepro/override dest="{{ETC}}/override-dsc.{{item.name}}"
    with_items: REPOS
  - template: src=files/reprepro/override dest="{{ETC}}/override-deb.{{item.name}}"
    with_items: REPOS
  - file: path="{{VAR}}/incoming/{{item.name}}" state=directory
    with_items: REPOS
  - file: path="{{VAR}}/tmp/incoming/{{item.name}}" state=directory
    with_items: REPOS
  - template: src=files/reprepro/build.sh dest="{{DIR}}/build.sh" mode=754
  - file: path="{{VAR}}" group=www-data mode=710
  - file: path="{{VAR}}" group=www-data mode=750 recurse=true
  # TODO: private/ keys install
  # TODO: ??? mdehaan fucked us:
  - include: tasks/nginx-confs.tasks hosts={{REPOS}} nginx="{{NGINX_ETC}}" conf="files/reprepro/nginx.conf"
  #- include: tasks/nginx-conf.tasks conf=files/reprepro/nginx.conf host="{{item.origin}}" ctx={{item}} name="{{nginx_prio}}-{{NAME}}" nginx={{NGINX_ETC}} service={{NGINX}} port=80
  #  with_items: REPOS
  #- include: tasks/systemd.alias.tasks src="{{NGINX}}" dest="{{NAME}}"
  - include: tasks/systemd.thunk.tasks service="{{NGINX}}"
