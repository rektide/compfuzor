---
- hosts: all
  gather_facts: False
  vars:
    TYPE: spark
    INSTANCE: main
    SYSTEMD_SERVICE: True
    SYSTEMD_EXEC: "{{DIR}}/bin/start-all.sh"
    SYSTEMD_TYPE: forking
    # Per-service config -> env.export + the unit's EnvironmentFile
    # (SYSTEMD_SERVICES_DEFAULT injects EnvironmentFile=-{{DIR}}/env when ENV is
    # set). SYSTEMD_ENV now means manager-wide publishing (the systemd-env
    # subsystem), which is wrong for per-service spark config.
    ENV:
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
  - import_tasks: tasks/compfuzor.includes
  - import_tasks: tasks/linkdir.includes
    vars:
      from: "{{OPTS_DIR}}/{{opt_origin}}"

  - shell: chdir="{{DIR}}" mv conf/* etc
  - file: path="{{DIR}}/conf" state=absent
  - file: src="{{DIR}}/etc" dest="{{DIR}}/conf" state=link
  
  - set_fact: line_var="slaves"
  - template: src=files/lines dest="{{ETC}}/slaves"
