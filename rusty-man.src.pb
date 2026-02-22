---
- hosts: all
  vars:
    REPO: git.sr.ht/~ireas/rusty-man
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
