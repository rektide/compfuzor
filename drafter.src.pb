---
- hosts: all
  vars:
    TYPE: drafter
    REPO: https://github.com/apiaryio/drafter
    INSTANCE: main
    PKGS: gyp
    ENV:
      PATH: "{{DIR}}/bin:$PATH"
    BINS:
    - name: build.sh
      run: True
      exec:
      - ./configure
      - make
    - name: drafter
      basedir: bin
      global: True
      src: False
  tasks:
  - include: tasks/compfuzor.includes type=src
