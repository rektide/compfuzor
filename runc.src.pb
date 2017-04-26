---
- hosts: all
  vars:
    TYPE: runc
    REPO: https://github.com/opencontainers/runc

    workspace: "{{OPT}}/workspace"
    OPT_DIRS:
    - workspace
    PKGS:
    - libseccomp-dev
    LINKS:
      "{{workspace}}/src/github.com/opencontainers/runc": "{{SRC}}"
    BINS:
    - name: build.sh
      basedir: "{{workspace}}"
      exec: make
    - name: runc
      global: True
      src: False
      basedir: "{{SRC}}"
      delay: postRun
    ENV:
      GOPATH: "${GOPATH-{{workspace}}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
