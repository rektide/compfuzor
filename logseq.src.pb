---
- hosts: all
  vars:
    TYPE: logseq
    INSTANCE: git
    REPO: https://github.com/logseq/logseq
    ETC_FILES:
      - name: .tool-versions
        content: |
          nodejs 18.13.0
          clojure 1.10.1.727
    LINKS:
      ".tool-versions": "{{ETC}}/.tool-versions"
    BINS:
      - name: build.sh
        execs:
          - yarn
          - yarn release
    PKGS:
      - rlwrap
  tasks:
    - include: tasks/compfuzor.includes type=src
