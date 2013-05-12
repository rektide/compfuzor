---
# bind9
# expects: zoneset - configuration file for a set of zones to load
- hosts: all
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    TYPE: bind
    INSTANCE: main
    ETC_DIRS:
    - named.conf.local.d
    - zone.d
    STOCK:
    - bind.keys
    - db.0
    - db.127
    - db.255
    - db.empty
    - db.local
    - db.root
    - named.conf.default-zones
    - zones.rfc1918
    ETC_FILES:
    - named.conf
    - named.conf.options
    CACHE_DIRS:
    - .
    LOG_DIRS:
    - .
    rndc_key: False
    user: bind
    port: 53
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  - files/bind/defaults.vars
  - [ "private/bind/$zoneset.vars", "private/bind9.vars" ]
  handlers:
  - include: handlers.yml
  tasks:
  - include: tasks/cfvar_includes.tasks
  - apt: state=${APT_INSTALL} pkg=bind9,bind9-doc,dnsutils
  - user: name=${user} system=true home={{DIR}}
  - template: src=files/bind/named.conf.local dest={{ETC}}/named.conf.local.d/${zoneset}.${item.name}.conf
    with_items: $domains
  - assemble: src={{ETC}}/named.conf.local.d dest={{ETC}}/named.conf.local
    notify: restart service
  - template: src=files/bind/zone dest={{ETC}}/zone.d/${item.name}.zone
    with_items: $domains
    notify: restart service
  - file: src=/etc/bind/$item dest={{ETC}}/$item state=link
    with_items: $STOCK
  - template: src=private/bind/rndc.key dest={{ETC}}/rndc.key
    only_if: "not not ${rndc_key}"
  - template: owner=root group=root src=files/bind/bind.service dest=/etc/systemd/system/{{NAME}}.service
    notify: restart service
