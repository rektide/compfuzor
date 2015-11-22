---
- hosts: all
  gather_facts: False
  vars:
    TYPE: bcc
    INSTANCE: git
    REPO: https://github.com/iovisor/bcc
    PKGS: 
    - libedit-dev
    - cmake
    # also requires llvm+clang 3.7
    PKGSET: devel
    BINS:
    - cmake.sh
  tasks:
  - include: tasks/compfuzor.includes
