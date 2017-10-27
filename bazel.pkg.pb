---
- hosts: all
  vars:
    TYPE: bazel
    INSTANCE: stable
    APT_REPO: http://storage.googleapis.com/bazel-apt
    APT_DISTRIBUTION: stable
    APT_COMPONENTS:
    - jdk1.8
  tasks:
  - include: tasks/compfuzor.includes type=pkg
