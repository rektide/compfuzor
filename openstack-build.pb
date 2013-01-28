---
- hosts: all
  user: rektide
  tags:
  - user
  gather_facts: False
  vars:
    TYPE: openstack-build
    INSTANCE: git
  vars_files:
  - "vars/common.vars"
  tasks:
  - include: tasks/opts.vars.tasks
  - git: repo=git://anonscm.debian.org/git/openstack/openstack-auto-builder.git dest=${DIR.stdout}
  - copy: src=files/openstack-build/build_openstack.compfuzor dest=${DIR.stdout}/build_openstack.compfuzor mode=774
- hosts: all
  tags:
  - packages
  - root
  sudo: True
  gather_facts: False
  vars_files:
  - vars/common.vars
  vars:
    pkgs:
    - python-all
    - python-setuptools-git
    - python-sphinx
    - python-nosexcover
    - python-eventlet
    - python-iso8601
    - python-keyring
    - python-cmd2
    - python-pyparsing
    - python-py
    - python-virtualenv
    - python-amqplib
    - python-anyjson
    - python-configobj
    - python-gflags
    - pylint
    - python-ldap
    - python-memcache
    - python-migrate
    - python-pam
    - python-passlib
    - python-paste
    - python-pastedeploy
    - python-routes
    - python-webob
    - python-webtest
    - sqlite3
    - python-boto
    - python-crypto
    - python-kombu
    - python-xattr
    - python-netifaces
    - python-openssl
    - bpython
    - euca2ools
    - ipython
    - python-babel
    - python-carrot
    - python-cheetah
    - python-distutils-extra
    - python-feedparser
    - python-libvirt
    - python-lockfile
    - python-netaddr
    - python-paramiko
    - python-qpid
    - python-suds
    - python-xenapi
    - python-sqlite
    - python-pyudev
    - python-requests
    - python-daemon
    - python-libxml2
    - python-pycurl
    - python-sqlalchemy-ext
    - python-mysqldb
    - python-django-nose
    - nodejs-legacy
    - node-less
    - python-dev
    - python-mock
    - pep8
    - python-prettytable
    - python-jsonschema
    - python-httplib2
    - python-mox
    - python-simplejson
    - python-unittest2
    - python-lxml
    - curl
    - python-all-dev
    - python-flask
    - python-ming
    - python-stevedore
    - libvirt-bin
    - python-zmq
    - python-testtools
    - python-tox
    - python-cliff
    - python-mako
    - python-pycryptopp
    - python-sendfile
    - python-yaml
  tasks:
  - apt: pkg=$pkgs state=$APT_INSTALL
