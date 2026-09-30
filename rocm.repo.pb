---
- hosts: all
  vars:
    TYPE: rocm
    INSTANCE: xenial
    # deb822 lane. Not deployed on workhorse; repo.radeon.com's debian
    # suites are ubuntu-codename based (last used: xenial).
    APT:
      URIs: http://repo.radeon.com/rocm/apt/debian/
      Suites: xenial
      Components: [main]
  tasks:
  - import_tasks: tasks/compfuzor.includes
    vars:
      type: pkg
