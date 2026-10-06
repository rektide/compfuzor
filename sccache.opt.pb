---
- hosts: all
  vars:
    TYPE: sccache
    INSTANCE: main
    USERMODE: true
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    BINS_RUN_BYPASS: true

    RUST_STORAGE_MISE_BIN: /usr/bin/mise
    SCCACHE_VERSION: 0.18.0
    SCCACHE_TOOL: "aqua:mozilla/sccache@{{SCCACHE_VERSION}}"
    SCCACHE_DIR: "{{XDG_CACHE_HOME}}/sccache"
    SCCACHE_CACHE_SIZE: 20G
    SCCACHE_MISE_CONFIG_DIR: "{{ ansible_env.MISE_CONFIG_DIR | default(XDG_CONFIG_HOME ~ '/mise', true) }}"
    ENV:
      CARGO_INCREMENTAL: '0'
    ZIM_ENV: [CARGO_INCREMENTAL]
    # Activate the existing contributor gate without adding any upstream modules.
    ZIM_MODULES: []

    README: |
      # sccache: shared Rust compiler cache

      Rendering is inert: no downloads, installation, daemon startup or user
      config edits. Defaults are user-only; no sudo or linger is needed.
      From this deployment, run `bin/build.sh` explicitly to install the pinned
      prebuilt `{{SCCACHE_TOOL}}` through `{{RUST_STORAGE_MISE_BIN}}` and link
      `bin/sccache` directly to its executable. Override `SCCACHE_VERSION`,
      `SCCACHE_TOOL`, or `RUST_STORAGE_MISE_BIN` at render time if needed.

      Before installing the service, stop any auto-started server with
      `bin/sccache --stop-server` (inspect other processes first). The service
      uses the default endpoint (port 4226): it must not compete with another
      server, and there must be only one server per cache. Installation links
      the managed mise drop-in and enables `{{NAME}}.service` in systemd --user.
      Installing starts it; rendering does not. No linger is enabled.
      WARNING: `bin/install-user.sh` also imports the generated Zim contributor
      described below. To install ONLY the daemon and mise client link, run
      `bin/install-systemd-user.sh` then `bin/install-links-user.sh` instead.
      Those selective lanes do not import the shell contribution.

      The drop-in is `{{SCCACHE_MISE_CONFIG_DIR}}/conf.d/compfuzor-sccache.toml`.
      It does not overwrite the main mise config or any Cargo config. Global
      conf.d entries are loaded by mise and trusted as global config (explicit
      ignored paths can still block them); no blanket trust command is run.
      Activate mise in a new shell, or use `mise exec -- cargo build` to consume
      its env. Existing main/project env overrides can take precedence.
      RUSTC_WRAPPER is the absolute deployment executable, SCCACHE_DIR is
      `{{SCCACHE_DIR}}`, and SCCACHE_CACHE_SIZE is `{{SCCACHE_CACHE_SIZE}}`.
      This disk-cache cap is approximate; it does not bound Cargo target trees.
      START_SERVER/NO_DAEMON are service-private, never client env settings.

      LIMITATION: sccache cannot cache incremental Rust compilations. This
      deployment renders ENV CARGO_INCREMENTAL=0 and projects it through ZIM_ENV
      into the normal generated Zim env module, proposing non-incremental builds.
      NOTHING has been installed or applied to your live shell by rendering.
      Importing the contributor later is an explicit shell-configuration action.
      Its existing don't-stomp policy preserves a non-empty CARGO_INCREMENTAL
      already set in the shell unless COMPFUZOR_ENV_OVERWRITE matches that key.
      The mise drop-in intentionally does not set CARGO_INCREMENTAL. Evaluate
      the loss of incremental compilation rather than assuming a running server
      means effective caching; explicit Cargo settings may also affect builds.
      rustup proxies are resolved by sccache using `rustup which rustc`.

      Inspect `bin/status.sh`, `bin/sccache --show-stats`, and
      `journalctl --user -u {{NAME}}.service`. A green service/link status is not
      proof that every Rust compilation is cacheable or using this wrapper.

      References: [compfuzor Rust storage](/doc/rust-storage/README.md),
      [sccache debugging](https://github.com/mozilla/sccache/blob/v0.18.0/README.md#debugging),
      [Rust limits](https://github.com/mozilla/sccache/blob/v0.18.0/docs/Rust.md),
      [local cache](https://github.com/mozilla/sccache/blob/v0.18.0/docs/Local.md),
      [mise configuration](https://mise.jdx.dev/configuration.html).

    ETC_FILES:
      - name: compfuzor-sccache.toml
        mode: '0644'
        content: |
          # Managed by compfuzor {{NAME}}; shared client env only.
          [env]
          RUSTC_WRAPPER = {{ (BINS_DIR ~ '/sccache') | to_json }}
          SCCACHE_DIR = {{ SCCACHE_DIR | to_json }}
          SCCACHE_CACHE_SIZE = {{ SCCACHE_CACHE_SIZE | to_json }}
    LINKS:
      - src: "{{ETC}}/compfuzor-sccache.toml"
        dest: "{{SCCACHE_MISE_CONFIG_DIR}}/conf.d/compfuzor-sccache.toml"
        scope: user

    SYSTEMD_SERVICE: "{{NAME}}"
    SYSTEMD_UNITS:
      Description: Shared Rust compiler cache (sccache)
    SYSTEMD_SERVICES:
      Type: exec
      ExecStart: "{{ (BINS_DIR ~ '/sccache') | replace('%', '%%') | replace('$', '$$') | to_json }}"
      Environment:
        - SCCACHE_START_SERVER=1
        - SCCACHE_NO_DAEMON=1
        - SCCACHE_IDLE_TIMEOUT=0
        - "{{ ('SCCACHE_DIR=' ~ SCCACHE_DIR) | replace('%', '%%') | to_json }}"
        - "{{ ('SCCACHE_CACHE_SIZE=' ~ SCCACHE_CACHE_SIZE) | to_json }}"
      Restart: on-failure
    SYSTEMD_INSTALLS:
      WantedBy: default.target

    BINS:
      - name: build-sccache.sh
        src: ../rust-storage/build-mise-tool.sh
        deployment_rooted: true
        env: false
        basedir: false
        phase: packages
        tool: "{{SCCACHE_TOOL}}"
        executable: sccache
        cache_dir: "{{SCCACHE_DIR}}"
      - name: status-sccache.sh
        basedir: false
        exec: |
          test -x {{ (BINS_DIR ~ '/sccache') | quote }}
          systemctl --user is-active {{ (NAME ~ '.service') | quote }}
    STATUSES: [status-sccache.sh]

  tasks:
    - import_tasks: tasks/compfuzor.includes
