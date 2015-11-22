---
- hosts: all
  vars:
    TYPE: antlr4-javascript
    INSTANCE: svn
    REPO: https://github.com/antlr/antlr4-javascript.git
    BINS:
    - exec: mvn install -DskipTests
  tasks:
  - include: tasks/compfuzor.includes type=src
