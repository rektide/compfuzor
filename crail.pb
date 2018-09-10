- hosts: all
  vars:
    TYPE: crail
    INSTANCE: git
    REPO: https://github.com/apache/incubator-crail
    BINS:
    - name: build.sh
      exec: |
        mvn install -DskipTests
  tasks:
  - include: tasks/compfuzor.includes type=src

