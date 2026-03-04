---
- hosts: all
  vars:
    REPO: https://github.com/argoproj/argo-cd
    PKGS:
      - passt
    BINS:
      - name: build.sh
        basedir: repo
        content: |
          export DOCKER=podman
          #make all
          #make argocd-all
          #make cli
          #make image
          #make build
          #make build-ui
          make cli-local
      - name: install.sh
        basedir: repo
        content: |
          #make install-tools-local
          make install-go-tools-local
  tasks:
    - import_tasks: tasks/compfuzor.includes
