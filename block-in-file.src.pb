---
- hosts: all
  vars:
    TYPE: block-in-file
    INSTANCE: git
    # The global standalone command must be reachable by fresh accounts,
    # not only members of the deployment owner's group.
    DIRMODE: "0755"
    REPO: https://github.com/jauntywunderkind/block-in-file
    # nodejs subsystem: build-nodejs.sh runs pnpm i --frozen-lockfile plus the
    # package `build` script (bundle + standalone) inside the local-first repo
    # checkout. NODEJS_BUILD_COMMANDS then promotes the dependency-free
    # standalone into the deployment dir: the repo lives under the admin's
    # 0700 archive, so shared consumers cannot exec from repo/dist directly.
    NODEJS: True
    NODEJS_BUILD_COMMANDS: >-
      install -D -m 0755 dist/block-in-file.standalone.mjs
      {{DIR}}/dist/block-in-file.standalone.mjs
    BINS:
      # Multi-user global command: the deployment bin is a plain link to the
      # promoted standalone, whose #!/usr/bin/env node shebang runs on any
      # user's stock node. `pnpm link -g` alone is per-admin and cannot serve
      # shared consumers. delay: postRun links only after the build promoted
      # the artifact.
      - name: block-in-file
        dest: block-in-file
        link: ../dist/block-in-file.standalone.mjs
        global: True
        delay: postRun
      - name: blockinfile
        state: absent
  tasks:
    - import_tasks: tasks/compfuzor.includes
