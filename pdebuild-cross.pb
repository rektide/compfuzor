---
- hosts: all
  vars:
    TYPE: pdebuildx
    INSTANCE: $ARCH
    ARCH: armel
    MULTISTRAPFILE: multistrap.conf
    BASETGZ: pdebuild-cross.tgz
    SUITE: sid
    ETC_FILES:
    - pdebuild-cross.rc
    - multistrap.conf
    DIRS:
    - .
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  gather_facts: false
  tasks:
  - include: tasks/cfvar_includes.tasks
  - name: test -e ${DIR.stdout}/$BASETGZ as NO_PDEBUILD_CROSS_BUILD
    shell: test -e ${DIR.stdout}/$BASETGZ; echo $?
    register: NO_PDEBUILD_CROSS_BUILD
  # TODO: HAZARD: it'd be swell if pdebuild-cross-create let us pass in a config file as a parameter. it doesn't, so smash the global config! http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=696756
  - file: path=/etc/pdebuild-cross/pdebuild-cross.rc state=absent
  - file: src=${ETC.stdout}/pdebuild-cross.rc dest=/etc/pdebuild-cross/pdebuild-cross.rc state=link
  # execute
  - shell: /usr/sbin/pdebuild-cross-create
    only_if: "${NO_PDEBUILD_CROSS_BUILD.stdout} > 0"
