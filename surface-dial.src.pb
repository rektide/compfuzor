---
- hosts: all
  vars:
    TYPE: surface-dial
    INSTANCE: git
    REPO: https://github.com/daniel5151/surface-dial-linux
    ENV:
      hi: ho
    PKGS:
      - libudev-dev
      - libevdev-dev
      - libhidapi-dev
    BINS:
      - name: build.sh
        exec: |
          cargo build -p surface-dial-daemon --release
      - name: install.sh
        exec: |
          ln -sv $(pwd)/target/release/surface-dial-daemon $GLOBAL_BINS_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes
