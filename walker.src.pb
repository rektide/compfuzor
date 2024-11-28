---
- hosts: all
  vars:
    TYPE: walker
    INSTANCE: git
    REPO: https://github.com/abenz1267/walker
    PKGS:
      - libgraphene-1.0-dev
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          go build ./cmd/walker.go
  tasks:
    - import_tasks: tasks/compfuzor.includes
