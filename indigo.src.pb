---
- hosts: all
  vars:
    TYPE: indigo
    INSTANCE: git
    REPO: https://github.com/bluesky-social/indigo
    BINS:
      - name: build.sh
        exec: |
          # of all the things not to build in the Makefile, doh
          go build ./cmd/goat
          # now do the rest
          make build
  tasks:
    - import_tasks: tasks/compfuzor.includes
