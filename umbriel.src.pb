---
- hosts: all
  vars_files:
    - vars/umbriel.yaml
  vars:
    TYPE: umbriel
    INSTANCE: git
    REPO: https://github.com/noctalia-dev/umbriel
    ENV: True

    # Upstream compiles this prefix into the binary so its packaged fallback
    # config can be found; configure and install must use the same value.
    UMBRIEL_PREFIX: /usr/local
    UMBRIEL_CLEAN_BUILD: false

    # Source-build dependencies should be present; do not use Compfuzor's
    # global `latest` default to upgrade the workhorse graphics/multilib stack.
    APT_INSTALL: present
    PKGS: "{{UMBRIEL_PKGS}}"
    ARCH_PKGS: "{{UMBRIEL_ARCH_PKGS}}"
  tasks:
    # Materialize the vars-file list through set_fact. A lazy play-var alias
    # remains an Ansible tagged scalar and merge_list treats it as one nested
    # bin item during synthesis.
    - name: publish Umbriel build actions
      set_fact:
        BINS: "{{UMBRIEL_ACTIONS}}"
    - import_tasks: tasks/compfuzor.includes
