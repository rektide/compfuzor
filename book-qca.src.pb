---
- hosts: all
  vars:
    TYPE: book-qca
    INSTANCE: git
    REPO: https://github.com/RrOoSsSsOo/QCA6174-samsung-galaxy-book-12-w720
    BINS:
    - name: install.sh
      content:
        chmod +x QCA6174.sh
        ./QCA6174.sh
  tasks:
  - include: tasks/compfuzor.includes type=src
