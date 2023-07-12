---
- hosts: all
  vars:
    TYPE: community-solid-server
    INSTANCE: main
    VAR_DIR: True

    src: "{{SRCS_DIR}}/{{TYPE}}-git"
    port: "3030"
    config: "@css:var/config.json"
    domain: "localhost"
    baseUrl: "{{domain}}:{{port|string}}"
    logLevel: debug
    rootFilePath: "./var/"
    ENV:
      CSS_BASE_URL: "{{baseUrl}}"
      CSS_CONFIG: "{{config}}"
      CSS_LOGGING_LEVEL: "{{logLevel}}"
      CSS_PORT: "{{port|string}}"
      CSS_CONFIG: "{{config}}"
      CSS_ROOT_FILE_PATH: "{{rootFilePath}}"
      CSS_SHOW_STACK_TRACE: true
      CSS_WORKERS: -1
      #CSS_MAIN_MODULE_PATH: ""
      #CSS_POD_CONFIG_JSON: ""
      #CSS_SEEDED_POD_CONFIG: ""

    SYSTEMD_SERVICE: True
    SYSTEMD_CWD: "{{dir}}"
    SYSTEMD_EXEC: "{{src}}/bin/server"
  tasks:
    - include: tasks/compfuzor.includes type=srv
