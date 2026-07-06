---
- hosts: all
  vars:
    REPO: https://github.com/facebook/fbthrift
    CMAKE: True
    CMAKE_INSTALL: True
    CMAKE_DEPS:
      folly: "{{OPTS_DIR}}/folly-{{INSTANCE|default('git')}}"
      fizz: "{{OPTS_DIR}}/fizz-{{INSTANCE|default('git')}}"
      rsocket: "{{OPTS_DIR}}/rsocket-{{INSTANCE|default('git')}}"
      wangle: "{{OPTS_DIR}}/wangle-{{INSTANCE|default('git')}}"
      yarpl: "{{OPTS_DIR}}/yarpl-{{INSTANCE|default('git')}}"
    PKGS:
    - flex
    - bison
    - libboost-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libmstch-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
