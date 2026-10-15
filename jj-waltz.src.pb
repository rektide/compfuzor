---
- hosts: all
  vars:
    REPO: https://github.com/EzraCerpac/jj-waltz
    GIT_REMOTES:
      rektide: https://github.com/rektide/jj-waltz
    # jj-style rev@remote: the rektide fork's reseed branch carries our
    # in-place CoW workspace reseeding on top of upstream (origin stays
    # upstream for diffing).
    GIT_VERSION: reseed-fork-20261015@rektide
    RUST: True
    RUST_BIN: jw
  tasks:
    - import_tasks: tasks/compfuzor.includes
