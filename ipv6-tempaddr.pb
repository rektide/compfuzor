---
# http://docs.menandmice.com/display/MM/enable+IPv6+privacy+extension+on+Ubuntu+Linux
- hosts: all
  vars:
    NAME: ipv6-tempaddr
    ETC_FILES:
    - ipv6-tempaddr.sysctl
  tasks:
  - include: tasks/compfuzor.includes
  - file: path=/etc/sysctl.conf.d state=directory
  - file: src="{{ETC}}/ipv6-tempaddr.sysctl" dest=/etc/sysctl.conf.d/ipv6-tempaddr.sysctl state=link
  - assemble: src=/etc/sysctl.conf.d dest=/etc/sysctl.conf
