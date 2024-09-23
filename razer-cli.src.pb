---
- hosts: all
  vars:
    TYPE: razer-cli
    INSTANCE: git
    REPO: https://github.com/LoLei/razer-cli.git
    BINS:
      - name: build.sh
        become: true
        run: true
        contents:
          python setup.py install
  tasks:
    - include: tasks/compfuzor.includes type=src
