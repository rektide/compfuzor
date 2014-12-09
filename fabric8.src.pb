---
- hosts: all
  tags:
  - build
  - maven
  gather_facts: False
  vars:
    NAME: fabric8
    TYPE: git
    REPO: https://github.com/fabric8io/fabric8
  tasks:
  - include: tasks/compfuzor.includes
  - shell: chdir={{DIR}} mvn -DskipTests clean install -Pall
  # find latest
  # link into SRCS_DIR


#MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=512m"
#mvn -DskipTests clean install -Pall
#cd fabric/fabric8-karaf/target
#unzip fabric8-karaf-1.2.0-SNAPSHOT.zip
#cd fabric8-karaf-1.2.0-SNAPSHOT 
