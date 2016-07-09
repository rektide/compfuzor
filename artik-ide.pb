---
- hosts: all
  vars:
    TYPE: artik-ide
    INSTANCE: git
    REPO: https://github.com/codenvy/artik-ide
    BINS:
    - name: build.sh
      exec: "cd {{DIR}}; mvn clean install"
  tasks:
  - include: tasks/compfuzor.includes type=src
