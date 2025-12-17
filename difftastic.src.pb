---
- hosts: all
  vars:
    TYPE: difftastic
    INSTANCE: git
    REPO: https://github.com/Wilfred/difftastic
    RUST: True
    RUST_BIN: difft
    ETC_FILES:
      - name: gitconfig
        content: |
          # TODO: installer
          # https://difftastic.wilfred.me.uk/git.html
          [alias]
            difft = -c diff.external=difft diff
            logt = -c diff.external=difft log --ext-diff
            showt = -c diff.external=difft show --ext-diff
  tasks:
    - import_tasks: tasks/compfuzor.includes
