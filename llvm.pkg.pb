---
- hosts: all
  vars:
    TYPE: llvm
    INSTANCE: main
    APT_REPO: http://apt.llvm.org/unstable/
    APT_DISTRIBUTION: llvm-toolchain
  tasks: 
  - include: tasks/compfuzor.includes type=pkg
