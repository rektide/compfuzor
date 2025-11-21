---
- hosts: all
  vars:
    TYPE: logseq
    INSTANCE: git
    REPO: https://github.com/logseq/logseq
    TOOL_VERSIONS:
      nodejs: True
      clojure: 1.11
    BINS:
      - name: watch.sh
        exec: |
          asdf install
          yarn
          yarn watch # then kill it after some time?!
          # yarn release
          # yarn release-electron
      - name: launch
        exec: |
          cd static
          # undesired having another build step in launch
          yarn
          cd ..
          yarn electron:dev
    PKGS:
      - rlwrap
    SYSTEMD_SERVICES:
  tasks:
    - import_tasks: tasks/compfuzor.includes
