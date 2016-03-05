---
- hosts: all
  vars:
    TYPE: dhcp-domain
    INSTANCE: yoyodyne-net
    domain: "{{INSTANCE|replace('-','.')}}"
    dhclient_conf: /etc/dhcp/dhclient.conf
    ETC_FILES:
    - "dhclient-domain.conf"
  tasks:
  - include: tasks/compfuzor.includes type=etc

  # create base dhclient.conf.d setup
  - file: path={{dhclient_conf}}.d state=directory
  - stat: path={{dhclient_conf}}.d/10-debian
    register: has_deb
  - raw: cp {{dhclient_conf}} {{dhclient_conf}}.d/10-debian
    when: not has_deb.stat.exists

  # link in our conf & assemble
  - file: src={{ETC}}/dhclient-domain.conf dest="{{dhclient_conf}}.d/50-domain-{{domain}}" state=link
  - assemble: src={{dhclient_conf}}.d dest={{dhclient_conf}}
