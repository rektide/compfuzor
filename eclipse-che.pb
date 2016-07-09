---
- hosts: all
  vars:
    TYPE: eclipse-che
    INSTANCE: git
    REPO: https://github.com/eclipse/che
    BINS:
    - name: build.sh
      exec: "cd {{DIR}}/assembly; mvn clean install"
  tasks:
  - include: tasks/compfuzor.includes type=src
