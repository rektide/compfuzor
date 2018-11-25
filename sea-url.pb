---
- hosts: all
  vars:
    TYPE: sea-url
    INSTANCE: git
    REPO: https://github.com/rektide/sea-url.git
    BINARIES:
    - seacurli
    - urlize
    BINS:
    - name: seaurli
      src: false
      basedir: "{{DIR}}"
      global: true
    - name: uget
      src: false
      basedir: "{{DIR}}"
      global: true
    - name: urlize
      src: false
      basedir: "{{DIR}}"
      global: true
  tasks:
  - include: tasks/compfuzor.includes type=src
