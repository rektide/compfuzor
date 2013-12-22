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
    - conf.d/11-master-lmtp.conf
    - conf.d/11-options.conf
    ETC_DIRS:
    - conf.d
    - private
    ETC_D:
    - conf.d/11-master-lmtp.conf
    #RUN_DIR: True
    SYSTEMD_SERVICE: True
    confd: /etc/dovecot/conf.d
    pems:
    - dovecot.pem
    - private/dovecot.pem
    etc_lookup: "{{ lookup('pipe', 'test -f ETC'+item+')+';echo $?' }}"
    postfix: postfix-main
    lmtp_location: private/dovecot-lmtp
    lmtp_pipe: "{{SPOOLS_DIR}}/{{postfix}}/{{lmtp_location}}"
    postconf_file: "/srv/{{postfix}}/etc/main.cf"
    lmtp_postfix_addr: "lmtp:unix:{{lmtp_location}}"
    lmtp_user: postfix
    lmtp_group: postfix
    lmtp_mode: "0600"
    modified_conf:
    - 20-lmtp.conf
  vars_files:
  - [ "private/dovecot.vars", "examples-private/dovecot.vars" ]
  tasks:
  - include: tasks/compfuzor.includes type=srv

  # copy defaults into place
  - include: tasks/linkdir.includes from="{{confd}}" to="{{ETC}}/conf.d"
  #- shell: chdir="{{confd}}" ls
  #  register: confd_files
  #- shell: "test -e {{ETC}}/conf.d/{{item}} || ln -s {{confd}}/{{item}} {{ETC}}/conf.d/{{item}}"
  #  with_items: confd_files.stdout_lines
  - shell: "test -e {{ETC}}/{{item}} || ln -s /etc/dovecot/{{item}} {{ETC}}/{{item}}"
    with_items: pems

  # modify specific conf.d files
  - file: path="{{ETC}}/conf.d/{{item}}" state=absent
    with_items: modified_conf
  - shell: cp -aurv "{{confd}}/{{item}}" "{{ETC}}/conf.d/{{item}}"
    with_items: modified_conf

  - lineinfile: dest="{{ETC}}/conf.d/20-lmtp.conf" regexp="postmaster_address\s+=\s+" line="  postmaster_address = {{postmaster}}" insertafter="^protocol\s+lmtp\s+{"
  - lineinfile: dest="{{postconf_file}}" regexp="^(mailbox|virtual)_transport\s*=\s*" line="mailbox_transport = {{lmtp_postfix_addr}}"
  - include: tasks/compfuzor.d.includes
