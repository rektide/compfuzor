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
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  - files/bind9/defaults.vars
  - [ "private/bind9/$zoneset.vars" ]
  handlers:
  - include: handlers.yml
  tasks:
  - include: tasks/cfvar_includes.tasks
  - apt: state=${APT_INSTALL} pkg=bind9,bind9-doc,dnsutils
  - template: src=files/bind9/named.conf.local dest=${ETC.stdout}/named.conf.local.d/${zoneset}.${item.name}.conf
    with_items: $domains
  - assemble: src=${ETC.stdout}/named.conf.local.d dest=${ETC.stdout}/named.conf.local
    notify: restart service
  - template: src=files/bind9/zone dest=${ETC.stdout}/zone.d/${item.name}.zone
    with_items: $domains
    notify: restart service
