---
- hosts: all
  vars:
    TYPE: pnpm
    INSTANCE: sys
    version: 12.6.0
    # Static system pnpm: self-contained release binary (no node, no mise,
    # no user env) promoted from /opt and linked into GLOBAL_BINS_DIR, so
    # root, cron, services, and /bin/sh builds all resolve pnpm. The tarball
    # layout (pnpm binary + dist/node-gyp-bin + dist/node_modules) mirrors
    # PNPM_HOME's; keep dist/ beside the linked binary. For the per-user
    # mise-managed flow see pnpm.opt.pb.
    GET_URLS:
      - url: https://github.com/pnpm/pnpm/releases/download/v{{version}}/pnpm-linux-x64.tar.gz
        dest: pnpm-linux-x64.tar.gz
    ENV:
      - version
    BINS:
      - name: install.sh
        run: True
        become: True
        content: |
          set -e
          rm -rf "${DIR}/dist"
          mkdir -p "${DIR}/dist"
          tar -xzf {{SRC}}/pnpm-linux-x64.tar.gz -C "${DIR}/dist"
          chmod 0755 "${DIR}/dist/pnpm"
          "${DIR}/dist/pnpm" --version
      - name: pnpm
        dest: pnpm
        link: ../dist/pnpm
        # delay: postRun links only after install.sh promoted the artifact
        # into dist/ during this same play run.
        global: True
        delay: postRun
  tasks:
    - import_tasks: tasks/compfuzor.includes
