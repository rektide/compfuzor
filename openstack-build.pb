---
- hosts: all
  user: rektide
  vars:
    TYPE: openstack
    INSTANCE: git
    repos:
    - cinder
    - factory-boy
    - glance
    - horizon
    - keystone
    - melange
    - munin-plugins-openstack
    - nagios-plugins-openstack
    - nova
    - novnc
    - openstack-auto-builder
    - openstack-common
    - openstack-meta-packages
    - openstack-pkg-tools
    - openstack.compute
    - openstack
    - openstackx
    - python-cinderclient
    - python-cliff
    - python-cloudfiles
    - python-django-appconf
    - python-django-compressor
    - python-django-openstack-auth
    - python-glanceclient
    - python-keystoneclient
    - python-melangeclient
    - python-novaclient
    - python-swiftclient
    - python-tox
    - python-warlock
    - quantum
    - swift
  vars_files:
  - "vars/common.vars"
  tasks:
  - include: tasks/opts.vars.tasks
  - file: path=${DIR.stdout} state=directory
  - copy: src=files/openstack/build dest=${DIR.stdout}/build mode=0755
  - git: repo=git://anonscm.debian.org/git/openstack/$item.git dest=${DIR.stdout}/$item
    with_items: $repos
