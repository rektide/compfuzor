---
- hosts: all
  vars:
    GET_URLS:
      - url: https://github.com/Adrilaw/OdinV4/releases/download/v1.0/odin.zip
        dest: odin.zip
      #- url: https://github.com/Adrilaw/OdinV4/archive/refs/tags/v1.0.tar.gz
      #  dest: odinv4-v1.0.tar.gz
    BINS:
      - name: build.sh
        content: |
          unzip src/odin.zip
  tasks: 
    - import_tasks: tasks/compfuzor.includes

