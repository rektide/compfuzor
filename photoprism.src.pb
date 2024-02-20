---
- hosts: all
  vars:
    TYPE: photoprism
    INSTANCE: git
    REPO: https://github.com/photoprism/photoprism
    PKGS:
      # helps tensorflow install
      - lshw
    BINS:
      - name: deps.sh
        content: |
      - name: build.sh
        content: |
          # https://docs.photoprism.app/developer-guide/setup/
          make dep
          make build-js
          make build-go

          # other random noted make targets follow:
          #make dep-js
          #make dep-tensorflow
          #make dep-go
          # util, upgrades deps past current
          #make upgrade
          #make dep-upgrade
          #make dep-upgrade-js
          # uh what?
          #make install-tensorflow
          #make install-go
          #make install-darktable
          # more what?
          #make build-prod
          #make build-tensorflow
  tasks:
    - include: tasks/compfuzor.includes type=src
