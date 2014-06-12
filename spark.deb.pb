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
  - shell: chdir="{{SRCS_DIR}}" ln -sf "{{DIR}}/assembly/target/spark_*.deb" . | awk '{ print $1 '}
    register: spark_deb
  - shell: chdir="{{SRCS_DIR}}" dpkg -i "{{spark_deb.stdout}}"
