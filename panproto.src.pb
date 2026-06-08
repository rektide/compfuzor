---
- hosts: all
  vars:
    REPO: https://github.com/panproto/panproto
    RUST: True
    # RUST_ALL installs all [[bin]] targets:
    #   panproto-cli -> schema
    #   panproto-git-remote -> git-remote-panproto
    RUST_ALL: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
