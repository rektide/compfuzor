---
# postfix
# expects: configset - configuration file for a set of zones to load
- hosts: all
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    TYPE: postfix
    INSTANCE: main
    ETC_FILES:
    - main.cf
    - aliases
    ETC_DIRS:
    - ssl
    VAR_DIRS:
    - .
    USER: postfix
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  - files/postfix/defaults.vars
  - [ "private/postfix/$configset.vars" ]
  handlers:
  - include: handlers.yml
  tasks:
  - include: tasks/cfvar_includes.tasks
  - apt: state={{APT_INSTALL}} pkg=postfix
  - user: name={{USER}} system=true home={{DIR}}
  # todo: notify restart service when ETC_FILES changed
  - template: src=files/postfix/postfix.service dest={{SYSTEMD_UNIT_DIR}}/{{NAME}}.service
    notify: restart service
  - shell: chdir={{ETC}} postalias aliases
  - file: path={{SPOOL}} state=directory owner={{USER}}
  - file: src=/etc/postfix/{{item}} dest={{ETC}}/{{item}} state=link
    with_items:
    - master.cf
    - post-install
    - postfix-script
  - file: path={{ETC}} mode=551 state=directory
  # create {{SPOOL}}/dev subsystem, including rsyslog
  - file: path={{SPOOL}}/dev state=directory
  - include: tasks/mknod.tasks path={{SPOOL}}/dev/random minor=8
  - include: tasks/mknod.tasks path={{SPOOL}}/dev/urandom minor=9
  # todo: check for rsyslog first
  # todo: notify rsyslog when changed
  - template: src=files/postfix/rsyslog.conf dest=/etc/rsyslog.d/{{NAME}}.conf

