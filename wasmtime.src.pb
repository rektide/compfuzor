---
- hosts: all
  vars:
    REPO: https://github.com/bytecodealliance/wasmtime
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
