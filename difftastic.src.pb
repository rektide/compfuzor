---
- hosts: all
  vars:
    TYPE: difftastic
    INSTANCE: git
    REPO: https://github.com/Wilfred/difftastic
    RUST: True
    RUST_BIN: difft
  tasks:
    - import_tasks: tasks/compfuzor.includes
