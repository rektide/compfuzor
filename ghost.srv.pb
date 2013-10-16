---
- hosts: all
  sudo: True
  vars:
    TYPE: ghost
    INSTANCE: git
    OPT: "/opt/{{NAME}}"
    SERVICE_EXEC: "node {{OPT}}/index {{ETC_DIR}}/config.js"
    ETC_FILES:
    - config.js
    VAR_DIR:
    - data
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  gather_facts: false
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/srv.user.tasks user={{USER}} home={{DIR}}
  - include: tasks/systemd.thunk.tasks service={{NAME}}
    only_if: ${has_service.changed}
