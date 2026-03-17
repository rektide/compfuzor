---
- hosts: all
  vars:
    REPO: https://github.com/argoproj/argo-cd
    PKGS:
      - passt
    ENV: True
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
        content: |
          #make install-tools-local
          #make install-go-tools-local
          ln -sfv $(dir)/repo/dist/argocd $GLOBAL_BINS_DIR
  tasks:
    - import_tasks: tasks/compfuzor.includes
