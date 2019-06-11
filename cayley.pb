---
- hosts: all
  vars:
    TYPE: cayley
    INSTANCE: git
    ENV:
      GOPATH: "{{DIR}}"
    REPO_GOGET: https://github.com/cayleygraph/cayley
    DIRS:
    - bin
    - pkg
    BINS:
    - name: build.sh
      run: True
      basedir: src/github.com/cayleygraph
      exec: |
        go build ./cmd/cayley
        
  tasks:
  - include: tasks/compfuzor.includes type=src
