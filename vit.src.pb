---
- hosts: all
  vars:
    REPO: https://github.com/solpbc/vit
    # nodejs subsystem: build-nodejs.sh imports package-lock.json into a
    # pnpm lockfile and installs. vit ships no `build` script — it runs
    # unbundled straight from bin/vit.js — so the default build-script probe
    # is a no-op and install-nodejs.sh's `pnpm link -g` is the whole install.
    # The link is per-admin (into ~/.local/share/pnpm), which suits vit: it is
    # a personal identity CLI whose login credentials live per-user anyway.
    NODEJS: True
    # pnpm 12 gates dependency build scripts and fails the install outright
    # when any were skipped. core-js (pulled by the atproto stack) only uses
    # its postinstall for a funding banner, so approve it explicitly.
    NODEJS_ALLOW_BUILDS:
      - core-js
    # vit's own postinstall always runs under pnpm — `npm_config_ignore_scripts`
    # cannot suppress root lifecycle scripts — and copies its using-vit skill
    # into ~/.claude/skills (claude-code). That copy is disposable upstream
    # noise: our authoritative registration is rekon's refs/GLOBAL.md row,
    # which symlinks the skill in place from ~/archive/solpbc/vit.
  tasks:
    - import_tasks: tasks/compfuzor.includes
