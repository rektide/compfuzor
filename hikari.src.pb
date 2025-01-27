---
- hosts: all
  vars:
    TYPE: hikari
    INSTANCE: main
    GET_URLS:
      - https://hikari.acmelabs.space/releases/hikari-2.3.3.tar.gz
    # TODO: darcs
    DARCS_REPO: http://hikari.acmelabs.space/
    BINS:
      - name: build.sh
        exec: |
          echo hi
  tasks:
    - import_tasks: tasks/compfuzor.includes
