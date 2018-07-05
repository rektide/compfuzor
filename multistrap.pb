---
- hosts: all
  vars:
    TYPE: multistrap
    INSTANCE: "amd64"
    MULTISTRAPFILE: multistrap.conf
    BASETGZ: multistrap.tgz
    ETC_FILES:
    - multistrap.conf
    - preseed
    - basic.parted
    #- preferences
    VAR_DIRS:
    - build
    BINS:
    - extract-from-tar.sh
    - disk-prep.sh
    - disk-gpt.sh
    - name: build
      run: True
    - name: post-create.sh
      run: True
    - name: multihack.sh
      content: |
        mkdir -p var/build/etc/apt/trusted.gpg.d
        cp -aur /etc/apt/trusted.gpg.d/debian*gpg var/build/etc/apt/trusted.gpg.d
    BINS_RUN_BYPASS: True
    BUILD_BYPASS:  False
    PKGS:
    - multistrap
    MODULES:
    - binfmt-misc
  vars_files:
  - vars/pkgs.yaml
  - [ "private/multistrap/$configset.yaml", "private/multistrap.yaml", "examples-private/multistrap.yaml" ]
  tasks:
  - shell: echo "no {{ARCH}} configured"; return 1
    when: ARCH is not defined
  - include: tasks/compfuzor.includes type=srv
  # already built? don't build again
  - name: test -e {{DIR}}/{{BASETGZ}} as NO_MULTISTRAP_BUILD
    shell: test -e {{DIR}}/{{BASETGZ}}; echo $?
    register: NO_MULTISTRAP_BUILD
  # execute
  - include: tasks/compfuzor/bins_run.tasks
    when: NO_MULTISTRAP_BUILD.stdout|int != 0 and not BUILD_BYPASS|default(False)
