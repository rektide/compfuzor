---
- hosts: all
  vars:
    TYPE: ripgrep
    INSTANCE: main
    USERMODE: True
    ZSHRC: "{{USERMODE|ternary(HOMEDIR + '.zshrc', '/etc/zsh/zshrc')}}"
    BASHRC: "{{USERMODE|ternary(HOMEDIR + '.bashrc', '/etc/bash.bashrc')}}"
    ETC_FILES:
    - name: rg.env
      content: alias rg='rg --color never --with-filename --no-heading --line-number'
    - name: "{{ZSHRC}}"
      line: "source \"{{ETC}}/rg.env\""
    - name: "{{BASHRC}}"
      line: "source \"{{ETC}}/rg.env\""
    LINKS:
      bashrc: "{{BASHRC}}"
      zshrc: "{{ZSHRC}}"
  tasks:
  - include: tasks/compfuzor.includes type=etc
