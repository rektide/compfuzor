---
- hosts: all
  gather_facts: False
  vars:
    TYPE: terra
    INSTANCE: git
    REPO: https://github.com/zdevito/terra
    PKGS:
    - clang-3.5
    - llvm-3.5
    BINS:
    - exec: make
  tasks:
  - include: tasks/compfuzor.includes type=src
