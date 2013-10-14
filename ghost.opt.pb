---
- hosts: all
  gather_facts: False
  vars:
    TYPE: ghost
    INSTANCE: git
    REPO: https://github.com/rektide/ghost
    gems:
    - bourbon
    - sass
  vars_files:
  - vars/common.vars
  - vars/opt.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir={{DIR}} git submodule update --init
  - shell: chdir={{DIR}} npm install
  - shell: chdir={{DIR}} gem install -i `pwd`/gems/{{item}} {{item}}
    with_items: gems
  - shell: chdir={{DIR}} PATH={{DIR}}/gems/sass/bin:{{DIR}}/gems/bourbon/bin:"$PATH" grunt
