---
- hosts: all
  user: rektide
  vars:
    TYPE: ansible
    INSTANCE: git
    REPO: https://github.com/ansible/ansible
    HOSTS_DIR: "{{CONFIG_DIRS}}/hosts"
  vars_files:
  - vars/common.vars
  - vars/opt.vars
  - vars/common.user.vars
  - vars/ansible.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/xdg.vars.tasks
  - include: tasks/one.dir.tasks a=$CONFIG_DIR b=~/.ansible
  #### hosts dir + default
  - include: tasks/one.dir.tasks a=~/.hosts b={{HOSTS_DIR}}
  - copy: src=files/ansible/hosts.localhost dest={{HOSTS_DIR}}/localhost
  - file: src={{HOSTS_DIR}}/localhost dest={{HOSTS_DIR}}/default state=link
  #### env setter helper
  - shell: test -e $CONFIG_DIR/$ANSIBLE_ENV && echo 1 || echo 0
    register: has_ansible_env
  - template: src=files/ansible/$ANSIBLE_ENV dest=$CONFIG_DIR/$ANSIBLE_ENV mode=0755
    when: has_ansible_env.stdout|int == 0
  #### link to install
  - shell: test -e $CONFIG_DIR/$INSTALL_LINK && echo 0 || echo 1
    register: need_install_link
  - file: src=$INSTALL_DIR dest=$CONFIG_DIR/$INSTALL_LINK state=link
    when: need_install_link.stdout|int > 0
  #### XDG_CONFIG_DIR/ansible install
  - name: check whether xdg_config_dir exists and is different from CONFIG_DIR:{{CONFIG_DIR}}
    shell: test -d "{{XDG_CONFIG_DIR}} -a "x{{XDG_CONFIG_DIR}}" != "x{{CONFIG_DIR}}" -a ! -e "{{XDG_CONFIG_DIR}}/ansible" && echo 1 || echo 0
    register: need_config_link
  - file: src={{CONFIG_DIR}} dest={{XDG_CONFIG_DIR}}/ansible state=link
    when: need_config_link.stdout|int > 0
  - file: src=$CONFIG_DIR/$ANSIBLE_ENV dest=$BINS_DIR/$ANSIBLE_ENV state=link
  ### install ansible-ec2
  - git: repo=https://github.com/pas256/ansible-ec2.git dest=$OPTS_DIR/ansible-ec2
  - file: src=$OPTS_DIR/ansible-ec2/ansible-ec2 dest=$BINS_DIR/ansible-ec2
  - file: src=$INSTALL_DIR/plugins/inventory/ec2.py dest={{HOSTS_DIR}}/ec2
  - file: src=$INSTALL_DIR/plugins/inventory/ec2.ini dest=$CONFIG_DIR/ec2.ini
- hosts: all
  user: root
  vars_files:
  - vars/common.vars
  tags:
  - deps
  tasks:
  #- include: tasks/ansible.deps.task
  #  when: not APT_BYPASS
