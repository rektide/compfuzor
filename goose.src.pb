---
- hosts: all
  vars:
    TYPE: goose
    INSTANCE: git
    REPO_GOGET: bitbucket.org/liamstask/goose/cmd/...
    BINS:
    - name: goose
      global: True
      src: False
  tasks:
  - include: tasks/compfuzor.includes type=src
