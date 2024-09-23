---
- hosts: all
  vars:
    TYPE: ocamlfuse
    INSTANCE: git
    REPO: https://github.com/astrada/gapi-ocaml
    PKGS:
      - ocaml-base
      - ocaml
      - ocaml-dune
      - camlidl
      - libfuse-dev
      #- ocurl
      - libcryptokit-ocaml-dev
      - libyojson-ocaml-dev
      - libxmlm-ocaml-dev
      - libounit-ocaml-dev
  tasks:
    - include: tasks/compfuzor.includes type=src
