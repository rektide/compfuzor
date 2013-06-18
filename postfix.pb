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
  - shell: chdir={{ETC}} postalias ${item}
    with_items:
    - aliases
  - file: path={{SPOOL}} state=directory owner={{USER}}
  - file: src=/etc/postfix/{{item}} dest={{ETC}}/{{item}} state=link
    with_items:
    - master.cf
    - post-install
    - postfix-script
  - file: path={{ETC}} mode=551 state=directory
  # create {{SPOOL}}/dev subsystem, including rsyslog
  - file: path={{SPOOL}}/dev state=directory
  - shell: test -c {{SPOOL}}/dev/random; echo $?
    register: NEED_RANDOM
  - shell: test -c {{SPOOL}}/dev/urandom; echo $?
    register: NEED_URANDOM
  - shell: chdir={{SPOOL}}/dev mknod -m 444 random c 1 8
    only_if: ${NEED_RANDOM.stdout}
  - shell: chdir={{SPOOL}}/dev mknod -m 444 urandom c 1 9
    only_if: ${NEED_URANDOM.stdout}
  # todo: check for rsyslog first
  # todo: notify rsyslog when changed
  - template: src=files/postfix/rsyslog.conf dest=/etc/rsyslog.d/{{NAME}}.conf

