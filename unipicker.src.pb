---
- hosts: all
  vars:
    TYPE: unipicker
    INSTANCE: git
    REPO: https://github.com/jeremija/unipicker
    BINS:
      - name: build.sh
        exec: |
          make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
