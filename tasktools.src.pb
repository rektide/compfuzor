---
- hosts: all
  gather_facts: False
  vars:
    TYPE: tasktools
    INSTANCE: git
    REPOS:
      taskd: https://git.tasktools.org/scm/tm/taskd.git
      task: https://git.tasktools.org/scm/tm/task.git
      kronisk: https://git.tasktools.org/scm/tm/kronisk.git
      tasksh: https://git.tasktools.org/scm/ex/tasksh.git
      vit: https://git.tasktools.org/scm/ex/vit.git
      vitapi: https://git.tasktools.org/scm/ut/vitapi.git
    PKGSET: devel
    PKGS:
    - cmake
    #- libgnutls28-dev
    BINS:
    - name: build
    - name: build-all
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
