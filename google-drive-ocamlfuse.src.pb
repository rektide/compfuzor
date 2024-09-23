---
- hosts: all
  vars:
    TYPE: google-drive-ocamlfuse
    INSTANCE: git
    REPO: https://github.com/astrada/google-drive-ocamlfuse
    PKGS:
      - ocaml-base
      - ocaml
      - ocaml-dune
      - libfindlib-ocaml
      - libsqlite3-ocaml
  tasks:
    - include: tasks/compfuzor.includes type=src
