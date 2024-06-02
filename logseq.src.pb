---
- hosts: all
  vars:
    TYPE: logseq
    INSTANCE: git
    REPO: https://github.com/logseq/logseq
    ETC_FILES:
      - name: .tool-versions
        content: |
          nodejs 18.20.3
          clojure 1.11.1.1413
    LINKS:
      ".tool-versions": "{{ETC}}/.tool-versions"
    BINS:
      - name: build.sh
        exec: |
          asdf install
          yarn && \
          yarn release-electron
          # ignoring release and release-app targets
    PKGS:
      - rlwrap
  tasks:
    - include: tasks/compfuzor.includes type=src
