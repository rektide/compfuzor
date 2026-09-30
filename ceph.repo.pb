---
- hosts: all
  vars:
    TYPE: ceph
    INSTANCE: main
    # deb822 lane. DEAD UPSTREAM (ceph.com/debian-firefly was the 2014-era
    # repo, wheezy suites; kept for archaeology) -- do not deploy.
    APT:
      URIs: http://ceph.com/debian-firefly/
      Suites: wheezy
      Components: [main]
  tasks:
  - import_tasks: tasks/compfuzor.includes
    vars:
      type: etc
