---
- hosts: all
  vars:
    TYPE: cpustat
    INSTANCE: git
    REPO_GOGET: github.com/uber-common/cpustat
    BINS:
    - global: cpustat
  tasks:
  - include: tasks/compfuzor.includes type=src
