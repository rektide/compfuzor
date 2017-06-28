---
- hosts: all
  vars:
    TYPE: zetcd
    INSTANCE: git
    REPO_GOGET: github.com/coreos/zetcd
    BIN_DIRS: True
    BINS:
    - name: build.sh
      run: True
      vars:
      - GOPATH
      exec: |
        go get -u github.com/coreos/zetcd/cmd/zetcd
        go get -u github.com/coreos/zetcd/cmd/zkctl
        go get -u github.com/coreos/zetcd/cmd/zkboom
    - name: zetcd
      src: False
      delay: postRun
      global: True
    - name: zkctl
      src: False
      delay: postRun
      global: True
    - name: zkboom
      src: False
      delay: postRun
      global: True
  tasks:
  - include: tasks/compfuzor.includes type=src
