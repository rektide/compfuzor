---
- hosts: all
  vars:
    REPO: https://github.com/facebook/fb303
    CMAKE: True
    CMAKE_DEPS:
      fbthrift: "{{OPTS_DIR}}/fbthrift-{{INSTANCE|default('git')}}"
      folly: "{{OPTS_DIR}}/folly-{{INSTANCE|default('git')}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
