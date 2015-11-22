---
- hosts: all
  vars:
    TYPE: antlr4
    INSTANCE: git
    REPO: https://github.com/antlr/antlr4
    BINS:
    - exec: mvn install -DskipTests
    - name: antlr4
      exec: 'java -Xmx512M -cp "{{DIR}}/tool/target/antlr4-4.5.2-SNAPSHOT.jar:$CLASSPATH" org.antlr.v4.Tool $*'
      run: False
      global: False
  tasks:
  - include: tasks/compfuzor.includes type=src
