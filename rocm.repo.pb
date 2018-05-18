- hosts: all
  vars:
    TYPE: rocm
    INSTANCE: "{{APT_DISTRIBUTION}}"
    APT_REPO: http://repo.radeon.com/rocm/apt/debian/
    APT_DISTRIBUTION: xenial
    APT_COMPONENTS:
    - main
  tasks:
  - include: tasks/compfuzor.includes type=pkg
