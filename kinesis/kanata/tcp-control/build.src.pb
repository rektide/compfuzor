---
- hosts: all
  vars:
    TYPE: kanata
    INSTANCE: a-build
    DIRMODE: "0755"
    # Separate deployment-local checkout: never edit the archive checkout
    # or install/replace /usr/bin/kanata or /usr/local/bin/kanata.
    REPO: https://github.com/jtroo/kanata
    ARCHIVE_DOWNLOAD: false
    REPO_DIR: "{{ DIR }}/source"
    GIT_VERSION: v1.12.0
    PKGS: [build-essential, pkg-config, libudev-dev]
    GLOBAL_BINS_BYPASS: true
    BINS:
      - name: build-kanata.sh
        run: false
        basedir: false
        generated: |
          # Explicit invocation only; needs cargo/rustc already available.
          # Real copy, not a symlink through a protected home directory.
          cargo build --manifest-path "{{ REPO_DIR }}/Cargo.toml" \
            --locked --release --bin kanata --no-default-features \
            --features tcp_server,cmd --target-dir "{{ DIR }}/target"
          install -m 0755 "{{ DIR }}/target/release/kanata" "{{ DIR }}/bin/kanata"
          "{{ DIR }}/bin/kanata" --help
  tasks:
    - import_tasks: ../../../tasks/compfuzor.includes
