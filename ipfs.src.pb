---
- hosts: all
  vars:
    TYPE: ipfs
    INSTANCE: main
    PKGSET: go
    REPO_GOGET: github.com/ipfs/go-ipfs/cmd/ipfs
  tasks:
  - include: tasks/compfuzor.includes
