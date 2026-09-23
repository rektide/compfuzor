---
- hosts: all
  vars:
    TYPE: block-in-file
    INSTANCE: git
    REPO: https://github.com/jauntywunderkind/block-in-file
    # Host prerequisites: node on PATH for the wrapper (system-wide), pnpm for
    # build.sh (admin environment; bins run through the BINS_SHELL zsh lane so
    # mise shims resolve). The wrapper executes the dependency-free standalone
    # bundle so any user with a stock node can run it — no npx/tsx/node_modules.
    BINS:
      - name: build.sh
        run: True
        deployment_rooted: True
        content: |
          pnpm install --frozen-lockfile
          pnpm build
      - name: block-in-file
        global: True
        basedir: False
        deployment_rooted: True
        content: |
          exec node "$DIR/dist/block-in-file.standalone.mjs" "$@"
      - name: blockinfile
        state: absent
  tasks:
    - import_tasks: tasks/compfuzor.includes
