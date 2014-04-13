---
- hosts: all
  gather_facts: False
  vars:
    TYPE: spark
    INSTANCE: main
    SYSTEMD_SERVICE: True
    SYSTEMD_EXEC: "{{DIR}}/bin/start-all.sh"
    SYSTEMD_TYPE: forking
    SYSTEMD_ENV:
      SPARK_MASTER_WEBUI_PORT: 11010
      SPARK_WORKER_CORES: 2
      SPARK_WORKER_WEBUI_PORT: 11011
      SPARK_WORKER_MEMORY: 768m
      SPARK_WORKER_INSTANCES: 2
      SPARK_JAVA_OPTS: "-Dspark.local.dir={{VAR}}"
    ETC_DIRS: True
    VAR_DIRS: True
    USER: rektide
    opt_origin: spark-git
    slaves:
    - localhost
  tasks:
  - include: tasks/compfuzor.includes type="srv"
  - include: tasks/linkdir.includes from="{{OPTS_DIR}}/{{opt_origin}}"

  - shell: chdir="{{DIR}}" mv conf/* etc
  - file: path="{{DIR}}/conf" state=absent
  - file: src="{{DIR}}/etc" dest="{{DIR}}/conf" state=link
  
  - set_fact: line_var="slaves"
  - template: src=files/lines dest="{{ETC}}/slaves"
