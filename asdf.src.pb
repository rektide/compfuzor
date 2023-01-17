---
- hosts: all
  vars:
    TYPE: asdf
    INSTANCE: git
    REPO: https://github.com/asdf-vm/asdf.git
    BINS:
      - name: install-user.sh
    plugins:
      clojure:  https://github.com/halcyon/asdf-clojure.git
      nodejs: https://github.com/asdf-vm/asdf-nodejs.git

  tasks:
    - include: tasks/compfuzor.includes type=src
  
