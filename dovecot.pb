---
- hosts: all
  gather_facts: False
  vars:
    TYPE: dovecot
    INSTANCE: main
    PKGS:
    - dovecot
    - dovecot-antispam
    - dovecot-core
    - dovecot-imapd
    - dovecot-managesieved
    - dovecot-sieve
    - dovecot-lmtp
    - opendkim
    - opendkim-tools
    DIRS:
    - .
  tasks:
  - include: tasks/compfuzor.includes type=srv
