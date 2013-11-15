---
- hosts: all
  gather_facts: False
  vars:
    TYPE: dovecot
    INSTANCE: main
    PKGS:
    - dovecot-antispam
    - dovecot-core
    - dovecot-imapd
    - dovecot-managesieved
    - dovecot-sieve
    - dovecot-lmtpd
    - opendkim
    - opendkim-tools
    - dspam
    - dspam-doc
    #- dspam-webfrontend
    ETC_FILES:
    - dovecot.conf
    ETC_DIRS:
    - conf.d
    - private
    #RUN_DIR: True
    confd: /etc/dovecot/conf.d
    pems:
    - dovecot.pem
    - private/dovecot.pem
    etc_lookup: "{{ lookup('pipe', 'test -f ETC'+item+')+';echo $?' }}"
  tasks:
  - include: tasks/compfuzor.includes type=srv
  - debug: msg="msg {{ETC}}"
  - shell: chdir="{{confd}}" ls
    register: confd_files
  - shell: "test -e {{ETC}}/conf.d/{{item}} || ln -s {{confd}}/{{item}} {{ETC}}/conf.d/{{item}}"
    with_items: confd_files.stdout_lines
  - shell: "test -e {{ETC}}/{{item}} || ln -s /etc/dovecot/{{item}} {{ETC}}/{{item}}"
    with_items: pems
