---
- hosts: all
  vars:
    TYPE: gapi-ocaml
    INSTANCE: git
    REPO: https://github.com/astrada/gapi-ocaml
    PKGS:
      - ocaml-base
      - ocaml
      - ocaml-dune
      - libfindlib-ocaml
      - libocamlnet-ocaml
      - libocamlnet-ssl-ocaml
    - include: tasks/compfuzor.includes type=src
