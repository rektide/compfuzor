- hosts: all
  vars:
    TYPE: esp-idf
    INSTANCE: "{{GIT_VERSION|replace('/', '-')}}"
    REPO: https://github.com/espressif/esp-idf
    GIT_VERSION: release/v2.1
    ENV:
      IDF_PATH: "{{DIR}}"
      PATH: "${IDF_PATH}/components/esptool_py/esptool:${IDF_PATH}/components/espcoredump:${IDF_PATH}/components/partition_table/:$PATH"
  tasks:
  - include: tasks/compfuzor.includes type=src
