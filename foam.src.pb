---
- hosts: all
  vars:
    TYPE: foam
    INSTANCE: git
    REPOS:
      foam: https://github.com/foambubble/foam
      foam-template: https://github.com/foambubble/foam-template
      foam-cli: https://github.com/foambubble/foam-cli
      markdown-links: https://github.com/foambubble/markdown-links
  tasks:
    - include: tasks/compfuzor.includes type=src
