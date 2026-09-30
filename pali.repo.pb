---
- hosts: all
  vars:
    TYPE: pali
    INSTANCE: main
    # deb822 lane. DEAD UPSTREAM (launchpad PPA, oneiric-era; kept for
    # archaeology) -- do not deploy.
    APT:
      URIs: http://ppa.launchpad.net/pali/pali/ubuntu
      Suites: oneiric
      Components: [main]
  tasks:
  - import_tasks: tasks/compfuzor.includes
    vars:
      type: etc
