---
- hosts: all
  gather_facts: False
  vars:
    TYPE: jnr
    INSTANCE: git
    REPO: https://github.com/jnr/jnr-all
    BINS:
    - exec: 'cd jffi; mvn install; sudo ln -s target/jni/`arch`-`uname`/libjff*so /usr/lib'
    - exec: 'cd jnr-ffi; mvn install'
    - exec: 'git submodule foreach "mvn install"'
  tasks:
  - include: tasks/compfuzor.includes type=src
