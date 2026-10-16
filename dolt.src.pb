---
- hosts: all
  vars:
    REPO: https://github.com/dolthub/dolt
    # dolt's Go module lives in repo/go (github.com/dolthub/dolt/go), so the
    # shared go subsystem does not fit this deployment: its build-go.sh runs
    # `go build` from repo root (not a Go module for this layout), and its
    # install-go.sh would repoint /usr/local/bin/dolt at repo/dolt instead of
    # the repo/go/dolt path the link already uses. Build explicitly from the
    # module root; GO stays off and the mise go pin is declared directly.
    BINS:
      - name: build-dolt.sh
        run: True
        basedir: repo/go
        generated: |
          go build -o dolt ./cmd/dolt
    TOOL_VERSIONS:
      go: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
