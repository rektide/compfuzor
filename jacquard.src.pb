---
- hosts: all
  vars:
    REPO: https://tangled.org/nonbinary.computer/jacquard
    RUST: True
    # RUST_ALL installs all [[bin]] targets across the workspace:
    #   jacquard, jacquard-codegen, lex-fetch, extract-schemas, ...
    RUST_ALL: True
  tasks: 
    - import_tasks: tasks/compfuzor.includes
