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
    GEM_HOME: "{{DIR}}/gems"
  vars_files:
  - vars/common.vars
  - vars/opt.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir={{DIR}} git submodule update --init
  - shell: chdir={{DIR}} npm install
  - shell: chdir={{DIR}} GEM_HOME={{GEM_HOME}} gem install {{item}}
    with_items: gems
  - shell: chdir={{DIR}} GEM_HOME={{GEM_HOME}} PATH={{GEM_HOME}}/bin bourbon install
  - shell: chdir={{DIR}} GEM_HOME={{GEM_HOME}} PATH={{GEM_HOME}}/bin:"$PATH" grunt
