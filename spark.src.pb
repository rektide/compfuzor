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
  - shell: chdir="{{DIR}}" ./make-distribution.sh --tgz
  - shell: chdir="{{DIR}}" ls *tar.gz
    register: gzs
  - fail: msg="inconnect number of distributions about; {{gzs.stdout_lines|length}}, expected 1"
    when: gzs.stdout_lines|length != 1
  - shell: mktemp --tmpdir=/tmp -d tmp-spark.XXXXXXXXXX
    register: tmp
  - shell: chdir="{{tmp.stdout}}" tar -xvzf "{{DIR}}/{{gzs.stdout}}"
  - file: path="{{OPT}}" state=directory
  - shell: chdir="{{OPT}}" rm -rf *
  - shell: chdir="{{OPTS_DIR}}" mv "{{tmp.stdout}}"/spark*/* "{{OPT}}"
  - file: path="{{tmp.stdout}}" state=absent
