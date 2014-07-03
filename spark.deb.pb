---
- hosts: all
  gather_facts: False
  vars:
    TYPE: spark
    INSTANCE: git
    REPO: https://github.com/apache/spark
    mvn_opts: "-Xmx2g -XX:MaxPermSize=512M -XX:ReservedCodeCacheSize=512m"
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/compfuzor.includes type="src"
  - shell: chdir="{{DIR}}" MAVEN_OPTS="{{mvn_opts}}" mvn -Phadoop-2.4 -Pdeb -DskipTests package
  - include: tasks/find_latest.tasks find="{{DIR}}/assembly/target/spark*.deb"
  - file: src="{{latest}}" dest="{{SRCS_DIR}}/{{latest|basename}}" state=link
  - file: src="{{SRCS_DIR}}/{{latest|basename}}" dest="{{SRCS_DIR}}/spark.deb" state=link
  - shell: chdir="{{SRCS_DIR}}" dpkg -i spark.deb
