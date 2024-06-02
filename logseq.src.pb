---
- hosts: all
  vars:
    TYPE: logseq
    INSTANCE: git
    REPO: https://github.com/logseq/logseq
    ETC_FILES:
      - name: ".tool-versions"
        content: |
          nodejs 18.20.3
          clojure 1.11.1.1413
    LINKS:
      ".tool-versions": "{{ETC}}/.tool-versions"
    BINS:
      - name: watch.sh
        basedir: True
        exec: |
          asdf install
          yarn
          yarn watch # then kill it after some time?!
          # yarn release
          # yarn release-electron
      - name: launch
        basedir: True
        exec: |
          cd static
          # undesired having another build step in launch
          yarn
          cd ..
          yarn electron:dev
    PKGS:
      - rlwrap
  tasks:
    - include: tasks/compfuzor.includes type=src
