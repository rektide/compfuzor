---
- hosts: all
  vars:
    TYPE: caddy
    INSTANCE: git
    REPO_GOGET:
    - github.com/mholt/caddy/caddy
    - github.com/caddyserver/builds
    BINS:
    - name: build.sh
      basedir: src/github.com/mholt/caddy/caddy
      exec: |
        go run build.go
      run: True
    - name: caddy
      src: False
      global: True
      delay: postRun
  tasks:
  - include: tasks/compfuzor.includes type=src
