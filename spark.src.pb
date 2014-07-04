---
- hosts: all
  gather_facts: False
  vars:
    TYPE: spark
    INSTANCE: git
    REPO: https://github.com/apache/spark
    GIT_DIR: "{{SRCS_DIR}}/{{NAME}}"
    OPTIONS:
    - with-tachyon
    - hadoop=2.4
    - skip-java-test
    LINKS:
      "{{SRC}}/dist": "{{DIR}}"
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/compfuzor.includes type="opt"
  - shell: chdir="{{SRC}}" ./make-distribution.sh --{{ OPTIONS|join(' --') }}
    environment:
      JAVA_HOME: "/usr/lib/jvm/default-java"
