---
# TODO: inoticoming to watch incoming
- hosts: all
  vars:
    TYPE: reprepro
    INSTANCE: main
    VAR_DIRS:
    - www/dists
    - www/pool
    - db
    - incoming
    - tmp/list
    - tmp/incoming
    DIRS:
    - .z
    FILES:
    - reprepro.env
    ETC_FILES:
    - distributions
    - options
    - incoming
    LINKS:
      dists: var/www/dists
      pool: var/www/pool
      .z/reprepro.env: reprepro.env
      conf: etc
    nginx_prio: 50
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  - private/reprepro.vars
  gather_facts: false
  handlers:
  - include: handlers.yml
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/template.tasks src=files/reprepro/override dest=${ETC.stdout}/override-dsc.${item.codename} content=${OVERRIDES_DSC}
    with_items: $REPOS
  - include: tasks/template.tasks src=files/reprepro/override dest=${ETC.stdout}/override-deb.${item.codename} content=${OVERRIDES_DEB}
    with_items: $REPOS
  - file: path=${VAR.stdout}/incoming/${item.codename} state=directory
    with_items: $REPOS
  - file: path=${VAR.stdout}/tmp/incoming/${item.codename} state=directory
    with_items: $REPOS
  # TODO: private/ keys install
  - include: tasks/nginx-conf.tasks conf=files/reprepro/nginx.conf host=${item.origin} ctx=${item} name=${nginx_prio}-${NAME.stdout} nginx=${NGINX_ETC} service=${NGINX}
    with_items: $REPOS
  - include: tasks/systemd.alias.tasks src={{NGINX}} dest={{NAME.stdout}}
- hosts: all
  sudo: True
  gather_facts: False
  tags:
  - packages
  - root
  vars_files:
  - vars/common.vars
  tasks:
  - apt: pkg=reprepro state=$APT_INSTALL
    only_if: not $APT_BYPASS
