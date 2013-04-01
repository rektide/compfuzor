---
- hosts: all
  gather_facts: false
  vars:
    TYPE: node
    INSTANCE: ${version}
    DIR_BYPASS: True
    version: v0.10.2
    base: node-${version}-linux-x64
    tarfile: ${base}.tar.gz
    urlfile: ${tarfile}.url
    repo: http://nodejs.org/dist/${version}/${tarfile}
    linkdir: ${SRCS_DIR}/node
    binaries:
    - npm
    - node
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/template.tasks src=files/trivial dest=$SRCS_DIR/$urlfile content=$repo
  #- lineinfile: dest=$SRCS_DIR/$urlfile regexp='^http' line=$repo create=yes
  - get_url: url=$repo dest=$SRCS_DIR/$tarfile
  - shell: chdir=$SRCS_DIR tar -xzf $tarfile
  - file: src=$SRCS_DIR/$base dest=$linkdir-$version state=link
  - file: src=$SRCS_DIR/$base dest=$linkdir state=link
  - file: src=$linkdir/bin/$item dest=$BINS_DIR/$item state=link
    with_items: $binaries
