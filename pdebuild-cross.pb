---
- hosts: all
  vars:
    TYPE: pdebuildx
    INSTANCE: "{{ARCH}}"
    MULTISTRAPFILE: multistrap.conf
    BASETGZ: pdebuild-cross.tgz
    ETC_FILES:
    - pdebuild-cross.rc
    - multistrap.conf
    - preseed
    - basic.parted
    #- preferences
    BINS:
    - extract-from-tar.sh
    - disk-prep.sh
    - name: post-create.sh
      run: True
    BINS_RUN_BYPASS: True
    BUILD_BYPASS:  true
    PKGS:
    - pdebuild-cross
    MODULES:
    - binfmt-misc
  vars_files:
  - vars/pkgs.vars
  - [ "private/pdebuild-cross/$configset.vars", "private/pdebuild-cross.vars", "examples-private/pdebuild-cross.vars" ]
  tasks:
  - shell: echo "no {{ARCH}} configured"; return 1
    when: ARCH is not defined
  - include: tasks/compfuzor.includes type=srv
  # already built? don't build again
  - name: test -e {{DIR}}/{{BASETGZ}} as NO_PDEBUILD_CROSS_BUILD
    shell: test -e {{DIR}}/{{BASETGZ}}; echo $?
    register: NO_PDEBUILD_CROSS_BUILD
  # TODO: HAZARD: it'd be swell if pdebuild-cross-create let us pass in a config file as a parameter. it doesn't, so smash the global config! http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=696756
  - file: path=/etc/pdebuild-cross/pdebuild-cross.rc state=absent
  - file: path=/etc/pdebuild-cross state=directory
  - file: src={{ETC}}/pdebuild-cross.rc dest=/etc/pdebuild-cross/pdebuild-cross.rc state=link
  # execute
  - shell: /usr/sbin/pdebuild-cross-create; echo $?
    when: NO_PDEBUILD_CROSS_BUILD.stdout|int != 0 and not BUILD_BYPASS|default(False)
  - include: tasks/compfuzor/bins_run.tasks
    when: NO_PDEBUILD_CROSS_BUILD.stdout|int != 0 and not BUILD_BYPASS|default(False)
