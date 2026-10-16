---
- hosts: all
  vars:
    TYPE: wrangler
    REPO: https://github.com/cloudflare/workers-sdk
    NODEJS: True
    NODEJS_LINK_DIR: packages/wrangler
    # libvips-dev on this host makes sharp's installer prefer a global-libvips
    # source build (requires node-gyp); the lockfile already installs the
    # packaged @img prebuilt, so skip the global search entirely.
    ENV:
      SHARP_IGNORE_GLOBAL_LIBVIPS: "1"
  tasks:
    - import_tasks: tasks/compfuzor.includes
