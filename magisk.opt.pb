---
- hosts: all
  vars:
    v: "30.6"
    GET_URLS:
      - url: "https://github.com/topjohnwu/Magisk/releases/download/v{{v}}/Magisk-v{{v}}.apk"
        dest: "Magisk-v{{v}}.apk"
  tasks:
    - import_tasks: tasks/compfuzor.includes
