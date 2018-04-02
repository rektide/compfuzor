---
- hosts: all
  vars:
    TYPE: ripgrep
    INSTANCE: user
    ETC_FILES:
    - name: rg.env
      content: alias rg='rg --color never --with-filename --no-heading --line-number'
    - name: ~/.zshrc
      lineinfile: source "{{ETC}}/rg.env"
  tasks:
  - include: tasks/compfuzor.includes type=user

