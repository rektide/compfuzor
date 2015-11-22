---
- hosts: all
  gather_facts: False
  # structure is also seen in vars_debconf
  #vars_files:
  #- [ "private/{{TYPE}}/selection/{{configset}}.vars",
  #    "private/{{TYPE}}/selection/{{TYPE}}.vars",
  #    "private/selection/{{configset}}.vars",
  #    "private/selection/{{TYPE}}.vars",
  #    "examples-private/{{TYPE}}/selection/{{configset}}.vars",
  #    "examples-private/{{TYPE}}/selection/{{TYPE}}.vars",
  #    "examples-private/selection/{{configset}}.vars",
  #    "examples-private/selection/{{TYPE}}.vars",
  #    "vars/empty.vars" ]
  #- [ "private/{{TYPE}}/selection/{{configset}}-overrides.vars",
  #    "private/{{TYPE}}/selection/{{TYPE}}-overrides.vars",
  #    "private/selection/{{configset}}-overrides.vars",
  #    "private/selection/{{TYPE}}-overrides.vars",
  #    "examples-private/{{TYPE}}/selection/{{configset}}-overrides.vars",
  #    "examples-private/{{TYPE}}/selection/{{TYPE}}-overrides.vars",
  #    "examples-private/selection/{{configset}}-overrides.vars",
  #    "examples-private/selection/{{TYPE}}-overrides.vars",
  #    "vars/empty.vars" ]
  #- [ "private/{{configset}}.vars",
  #    "private/{{TYPE}}.vars",
  #    "examples-private/{{configset}}.vars",
  #    "examples-private/{{TYPE}}.vars",
  #    "vars/empty.vars" ]
  vars:
    TYPE: metamaps-cc
    INSTANCE: git
    REPO: https://github.com/metamaps/metamaps_gen002.git
    PKGS:
    - nodejs
    - libpq-dev
    - bundler
    - imagemagick
    DBCONFIG: True
    # NEEDS:
    #- redis
    #- postgres
    BINS:
    - build.sh

    SYSTEMD_SERVICE: True
    SYSTEMD_CWD: "{{DIR}}/repo"
    SYSTEMD_EXEC: "rails server -p {{port}}"
    port: 3000
  tasks:
  - include: tasks/compfuzor.includes type=srv
