---
- hosts: all
  vars:
    TYPE: bandwhich
    INSTANCE: git
    REPO: https://github.com/imsnif/bandwhich
    BINS:
      - name: build.sh
        content: |
          cargo build --release
      - name: install.sh
        content: |
          sudo setcap cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep $(command -v bandwhich)
          sudo cp --reflink=auto $DIR/target/release/bandwhichd /usr/local/bin/bandwhich
      - name: run.sh
        content:
          sudo $DIR/target/release/bandwhich
    ENV: {}
  tasks:
    - include: tasks/compfuzor.includes type=src
