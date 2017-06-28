---
- hosts: all
  vars:
    TYPE: pravega
    INSTANCE: git
    REPO: https://github.com/pravega/pravega
    BINS:
    - name: build.sh
      exec: ./gradlew distribution
  tasks:
  - include: tasks/compfuzor.includes type=src
