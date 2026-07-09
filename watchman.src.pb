---
# Watchman built via Meta's getdeps.py — the hermetic build orchestrator that
# ships at build/fbcode_builder/getdeps.py in every fbcode OSS repo (this is
# what CI uses, per the README).
#
# Replaces the manual CMAKE_DEPS chain (folly/fizz/fbthrift/rsocket/wangle +
# ~15 transitive -dev packages) that was fighting system-folly pollution,
# version skew, and GCC-15 header breakage. getdeps reads pinned manifests,
# fetches every dep's source, builds them in topo order, and installs each
# into $DIR/<dep>/ subdirs. No system pollution — everything lives under $DIR.
#
# Two-phase build (getdeps's recommended split for fast iteration):
#   1. build-deps.sh (--only-deps): builds folly/fizz/fbthrift/mvfst/wangle
#      + ~20 lower-level libs. Slow (30+ min first run), idempotent after.
#   2. build.sh      (--no-deps):   rebuilds only watchman against the deps
#      already installed under $DIR/. Fast for iteration.
#   3. install.sh: symlinks the binary into $GLOBAL_BINS_DIR.
#
# No CMAKE subsystem — getdeps runs its own cmake internally with the correct
# -DCMAKE_PREFIX_PATH auto-wired from the installed deps.
#
# PREREQS / WORKAROUNDS (needed against 2025-07 watchman HEAD):
#
# 1. liburing.src.pb must be installed first. folly HEAD uses io_uring zcrx
#    UAPI symbols (ZCRX_REG_IMPORT, IORING_REGISTER_ZCRX_CTRL, ...) that are
#    absent from Debian's liburing-dev 2.14 bundled io_uring.h. We export
#    CMAKE_PREFIX_PATH pointing at /opt/liburing-git so folly's find_package
#    (LibUring) picks up the newer headers.
#
# 2. --extra-cmake-defines CMAKE_POLICY_VERSION_MINIMUM=3.5: some deps
#    (cpptoml 0.1.2) declare cmake_minimum_required(VERSION 2.x) which modern
#    cmake rejects. This policy override lets them configure anyway.
#
# 3. Boost manifest patch: edit build/fbcode_builder/manifests/boost in the
#    watchman checkout to remove --with-python from [b2.args]. Boost 1.83.0's
#    numpy bindings are incompatible with NumPy 2.x (PyArray_Descr->elsize
#    removed). Watchman doesn't use boost.python. This is a tracked file so
#    it'll be overwritten on git pull — re-apply if boost fails to build.
- hosts: all
  vars:
    REPO: https://github.com/facebook/watchman
    BINS:
      - name: build-deps.sh
        # Manual first run (slow). getdeps skips already-installed deps on
        # re-run, so it's safe to invoke repeatedly. Not auto-run because it
        # takes 30+ min on a clean tree.
        basedir: repo
        generated: |
          export CMAKE_PREFIX_PATH="{{OPTS_DIR}}/liburing-{{INSTANCE|default('git')}}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
          python3 build/fbcode_builder/getdeps.py \
            --scratch-path "$DIR/scratch" \
            --install-prefix "$DIR" \
            --allow-system-packages \
            --extra-cmake-defines '{"CMAKE_POLICY_VERSION_MINIMUM":"3.5"}' \
            build --only-deps watchman
      - name: build.sh
        run: true
        basedir: repo
        generated: |
          export CMAKE_PREFIX_PATH="{{OPTS_DIR}}/liburing-{{INSTANCE|default('git')}}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
          python3 build/fbcode_builder/getdeps.py \
            --scratch-path "$DIR/scratch" \
            --install-prefix "$DIR" \
            --allow-system-packages \
            --extra-cmake-defines '{"CMAKE_POLICY_VERSION_MINIMUM":"3.5"}' \
            build --no-deps --src-dir . watchman
      - name: install.sh
        basedir: false
        generated: |
          [ -n "${INSTALL_BIN-}" ] || INSTALL_BIN="watchman"
          ln -sfv "$DIR/watchman/bin/${INSTALL_BIN}" "$GLOBAL_BINS_DIR/${INSTALL_BIN}"
    # Only build tooling needed at the system level — getdeps builds all
    # fbcode deps (folly, fizz, fbthrift, etc.) and lower-level libs (openssl,
    # zlib, zstd, ...) from pinned source under $DIR/scratch/.
    PKGS:
      - python3
      - cmake
      - ninja-build
      - pkg-config
      - build-essential
      - autoconf
      - automake
      - libtool
  tasks:
    - import_tasks: tasks/compfuzor.includes
