---
- hosts: all
  vars:
    TYPE: dgraph
    INSTANCE: git
    REPO_GOGET: "github.com/dgraph-io/dgraph/..."
  tasks:
  - include: tasks/compfuzor.includes type=src
