---
- hosts: all
  vars:
    TYPE: logseq
    INSTANCE: git
    REPO: https://github.com/logseq/logseq
    ETC_FILES:
      - name: ".tool-versions"
        format: yaml
        content:
          nodejs 22
          clojure 1.11
    LINKS:
      - src: "{{DIR}}/etc/.tool-versions"
        #TODO: would be nice to have FS_CONTAINER compact via an 'include: etc'
        dest: ".tool-versions"
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
  tasks:
    - import_tasks: tasks/compfuzor.includes
