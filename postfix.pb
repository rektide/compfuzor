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
    - "main.cf.d/10-main.cf"
    - "main.cf.d/20-tls.cf"
    - aliases
    - "ssl/key.pem"
    - "ssl/cert.pem"
    - "ssl/REGEN"
    ETC_DIRS:
    - ssl
    - main.cf.d
    VAR_DIRS:
    - .
    USER: postfix
    PKGS:
    - postfix
    - postfix-doc
    - postfix-cdb
    - postfix-pcre
    - postfix-ldap
    - sasl2-bin
    - libsasl2-2
    SYSTEMD_SERVICE: postfix.service
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  - files/postfix/defaults.vars
  - [ "private/postfix/$configset.vars", "private/postfix.vars" ]
  handlers:
  - include: handlers.yml
  tasks:
  - include: tasks/compfuzor.includes type=srv
  #- user: name={{USER}} system=true home={{DIR}}
  # todo: notify restart service when ETC_FILES changed
  - shell: chdir={{ETC}} postalias aliases
  - include: tasks/linkdir.includes from="/etc/postfix" to="{{ETC}}"
  - assemble: src="{{ETC}}/main.cf.d" dest="{{ETC}}/main.cf"
  - file: path={{SPOOL}} state=directory owner={{USER}}
  - file: path={{ETC}} mode=551 state=directory
  # create {{SPOOL}}/dev subsystem, including rsyslog
  - file: path={{SPOOL}}/dev state=directory
  - include: tasks/mknod.tasks nod="{{SPOOL}}/dev/random" nod_type="c" minor="8"
  - include: tasks/mknod.tasks nod="{{SPOOL}}/dev/urandom" nod_type="c" minor="9"
  # todo: check for rsyslog first
  # todo: notify rsyslog when changed
  - template: src=files/postfix/rsyslog.conf dest=/etc/rsyslog.d/{{NAME}}.conf
