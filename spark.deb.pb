---
- hosts: all
  gather_facts: False
  vars:
    TYPE: spark
    INSTANCE: git
    REPO: https://github.com/apache/spark
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/compfuzor.includes type="src"
  - shell: chdir="{{DIR}}" SCALA_HOME=/usr SCALA_LIB_PATH=/usr/share/java MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=128M" mvn -Phadoop2-yarn,deb,repl-bin install package -DskipTests
  - shell: dpkg -i {{DIR}}/repl-bin/target/spark*deb
