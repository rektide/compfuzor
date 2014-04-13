---
- hosts: all
  gather_facts: False
  vars:
    TYPE: samba
    INSTANCE: main
    REPO: git://git.samba.org/samba.git
    APT_INSTALL: installed
    PKGS:
    - build-essential
    - libacl1-dev
    - libattr1-dev
    - libblkid-dev
    - libgnutls-dev
    - libreadline-dev
    - python-dev
    - python-dnspython
    - gdb
    - pkg-config
    - libpopt-dev
    - libldap2-dev
    - dnsutils
    - libbsd-dev
    - attr
    - krb5-user
    - docbook-xsl
    - libcups2-dev
    - acl
    - libpam0g-dev
    - xsltproc
    - libkrb5-dev
    - libtalloc-dev
    - libtevent-dev
    - libcephfs-dev
    - libavahi-client-dev
    - libctdb-dev
    - xfslibs-dev
    - libaio-dev
    - libfam-dev
    - libdm0-dev
    - yapps2
    - libnss3-dev
    - libbind-dev
    # conflicts with libkrb5-dev which is needed for libcups2-dev
    #- heimdal-dev
    ENABLE:
    - cups
    - iprint
    - avahi
    - fhs
    WITH:
    - winbind
    - ads
    - ldap
    - pam
    - pam_smbpass
    - quotas
    - sendfile-support
    - utmp
    - acl-support
    - dnsupdate
    - syslog
    - automount
    - aio-support
    - dmapi
    - fam
    - cluster-support
    - regedit
    # FreeIPA, but won't get a DC?
    #- with-system-mitkrb5
    #PREFIX: "{{OPT}}"
    PREFIX: /usr
  tasks:
  - include: tasks/compfuzor.includes type=src
  - shell: chdir={{DIR}} ./configure --with-{{ WITH|join(' --with-') }} --enable-{{ ENABLE|join(' --enable-') }} --prefix="{{PREFIX}}"
  - shell: chdir={{DIR}} make
  - shell: chdir={{DIR}} make install
