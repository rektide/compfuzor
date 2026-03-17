---
- hosts: all
  vars:
    REPO: https://github.com/bytecodealliance/wasm-tools
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
