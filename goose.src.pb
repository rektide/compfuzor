---
- hosts: all
  vars:
    NAME: goose
    TYPE: git
    REPO_GOGET: bitbucket.org/liamstask/goose/cmd/goose
  tasks:
  - include: tasks/compfuzor.includes type=src
