---
- hosts: all
  sudo: True
  sudo_user: root
  vars:
    TYPE: pdebuildx
    ARCH: amd64
    INSTANCE: $ARCH
    MULTISTRAPFILE: multistrap.conf
    BASETGZ: pdebuild-cross.tgz
  vars_files:
  - vars/common.vars
  gather_facts: false
  tasks:
  - include: tasks/srv.vars.tasks
  - include: tasks/dd.vars.tasks
  - file: path=$item state=directory
    with_items:
    - ${DIR.stdout}
    - ${ETC.stdout}
  # TODO: do not overwrite these config files if existing.
  - template: src=files/pdebuilder-cross/pdebuild-cross.rc dest=${ETC.stdout}/pdebuild-cross.rc
  - template: src=files/pdebuilder-cross/multistrap.conf dest=${ETC.stdout}/$MULTISTRAPFILE
  # TODO: HAZARD: it'd be swell if pdebuild-cross-create let us pass in a config file as a parameter. it doesn't, so smash the global config! http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=696756
  - file: path=/etc/pdebuild-cross/pdebuild-cross.rc state=absent
  - file: src=${ETC.stdout}/pdebuild-cross.rc dest=/etc/pdebuild-cross/pdebuild-cross.rc state=link
  # execute
  - shell: /usr/sbin/pdebuild-cross-create
    only_if: "${NO_PDEBUILD_CROSS_BUILD.stdout} > 0"
  #- include: tasks/dd.pdebuild.helper.tasks
