---
- hosts: all
  gather_facts: false
  vars:
    TYPE: flink
    INSTANCE: git
    REPO: https://github.com/apache/flink
    #PKGSET: java
    BINS:
    - exec: mvn install -DskipTests -Drat.skip=true
  tasks:
  - include: tasks/compfuzor.includes type=src
