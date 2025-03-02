---
- hosts: all
  vars:
    TYPE: hikari
    INSTANCE: main
    version: 2.3.3
    ENV:
      VERSION: "{{version}}"
    GET_URLS:
      - "https://hikari.acmelabs.space/releases/hikari-{{version}}.tar.gz"
    # TODO: darcs
    DARCS_REPO: http://hikari.acmelabs.space/
    PKGS:
      - bmake
      - libucl-dev
    BINS:
      - name: build.sh
        exec: |
          if [ ! -e hikari ]
          then
            echo extracting >&2
            tar -xvzf hikari-$VERSION.tar.gz
            echo linking >&2
            ln -s hikari-$VERSION hikari
            echo building
          fi
          cd hikari
          bmake WITH_ALL=YES
  tasks:
    - import_tasks: tasks/compfuzor.includes
