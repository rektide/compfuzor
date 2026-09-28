---
- hosts: all
  vars:
    TYPE: dl
    INSTANCE: git
    # The archive lane keeps Git+jj at ~/archive/rektide/dl and creates a
    # dedicated colocated jj/Git workspace at this deployment's `repo` path.
    REPO: https://github.com/rektide/dl
    GIT_VERSION: main
    TOOL_VERSIONS:
      pnpm: True
      nodejs: True
    ENV: True
    # dl is the house archive tool (~->~/archive/<org>/<repo>); this playbook
    # brings its own deployment under compfuzor management. The build installs
    # into the deployment workspace and (re)points the pnpm
    # global `dl` shim at the managed checkout.
    BINS:
      - name: build.sh
        content: |
          set -eu
          cd "{{DIR}}/repo"
          pnpm install
          # Repoint the global dl shim at this managed checkout. node_modules,
          # facts.db, and wf.db are gitignored in the deployment workspace.
          pnpm link --global
    README: |
      # dl — repository/packaging archive CLI

      `dl` downloads repositories, packages, org listings, and wikis into the
      house archive layout `~/archive/<org>/<repo>` — the same convention
      compfuzor's `ARCHIVE_DOWNLOAD` lane and the `archive/` jj toolkit lean
      into. This playbook manages a deployment of it.

      ## Layout

      - Canonical jj archive: `~/archive/rektide/dl`, refreshed by
        [`repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks) via
        the [`archive/`](/archive/README.md) toolkit (`GIT_VERSION: main`).
      - Deployment dir (`{{DIR}}` with `-e USERMODE=True`): generated env plus
        the dedicated `repo` jj workspace and Git worktree.
      - Build: `pnpm install` in the deployment workspace (node_modules and
        the facts/wf databases are gitignored), then `pnpm link --global`.

      ## The global shim

      After a build, `dl` on PATH resolves to this managed checkout. A legacy
      checkout at `~/src/dl` is left untouched (compfuzor does not prune
      undeclared artifacts); to switch back to it run
      `cd ~/src/dl && pnpm link --global`, and migrate it deliberately (see
      `script/deprecated-harvest-legacy-repo.sh`) when ready.

      ## Run

          ansible-playbook -i 'localhost,' -c local dl.src.pb -e USERMODE=True

      Verify with `dl --version` and `which dl` after the build.
  tasks:
    - import_tasks: tasks/compfuzor.includes
