---
- hosts: all
  vars:
    TYPE: headscale
    INSTANCE: git
    REPO_GO: https://github.com/juanfont/headscale
  tasks:
    - include: tasks/compfuzor.includes types=src
