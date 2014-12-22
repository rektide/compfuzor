---
- hosts: all
  gather_facts: False
  vars:
    TYPE: metamaps
    INSTANCE: git
    REPO: https://github.com/metamaps/metamaps_gen002.git
    PKGS:
    - nodejs
    - libpq-dev
    - bundler
    # NEEDS:
    #- redis
    #- postgres
    BINS:
    - exec: "bundle install --path vendor/bundle"
  tasks:
  - include: tasks/compfuzor.includes
