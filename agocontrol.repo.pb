---
- hosts: all
  vars:
    TYPE: agocontrol
    INSTANCE: main
    # deb822 lane. DEAD UPSTREAM (mirror.at.agocontrol.com is long gone;
    # kept for archaeology) -- do not deploy.
    APT:
      URIs: http://mirror.at.agocontrol.com/debian
      Suites: unstable
      Components: [main]
  tasks:
  - import_tasks: tasks/compfuzor.includes
    vars:
      type: etc
