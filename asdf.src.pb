---
- hosts: all
  vars:
    TYPE: asdf
    INSTANCE: git
    REPO: https://github.com/asdf-vm/asdf.git
    BINS:
      - name: install-user.sh
    ETC_FILES:
      - name: plugins.json
        content: "{{plugins|to_nice_json}}"
    plugins:
      - name: java
        version: openjdk-20
      - name: clojure
        url: https://github.com/halcyon/asdf-clojure.git
      - name: deno
      - name: nodejs
      - name: protonge
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
