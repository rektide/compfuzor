---
- hosts: all
  vars:
    TYPE: lg-dev-manager
    INSTANCE: main
    VERSION: 1.99.13
    GET_URLS:
      - "https://github.com/webosbrew/dev-manager-desktop/releases/download/v{{VERSION}}/webos-dev-manager_{{VERSION}}_amd64.deb"
    VAR_DIRS:
      - foo
  tasks:
    - import_tasks: tasks/compfuzor.includes

