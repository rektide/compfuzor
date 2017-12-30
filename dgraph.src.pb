---
- hosts: all
  vars:
    TYPE: dgraph
    INSTANCE: git
    REPO_GOGET: "github.com/dgraph-io/dgraph/..."
    BINS:
    - name: dgraph
      src: False
      global: True
    - name: dgraphloader
      src: False
      global: True
  tasks:
  - include: tasks/compfuzor.includes type=src
