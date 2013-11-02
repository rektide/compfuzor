---
- hosts: all
  user: rektide
  var:
    INSTALL_DIR: {{OPTS_DIR}}
    HOSTS_DIR: "{{CONFIG_DIR}}/hosts"
    aliases:
    - hosts
    - ansible/hosts
  vars_files:
  - vars/common.vars
  - vars/common.user.vars
  - vars/ansible.vars
  tasks:
  - include: "tasks/xdg.vars.tasks"
  - file: path=$CONFIG_DIR state=directory
  - include: tasks/one.dir.tasks a=$CONFIG_DIR b=~/.ansible
  - file: path=$INSTALL_DIR state=directory
  #### default hosts file
  - file: path={{HOSTS_DIR}} state=directory
  - file: src={{HOSTS_DIR}} dest=~/.{{item}} state=link
    with_items: aliases
  - copy: src=files/ansible/$DEFAULT_HOSTS dest=~/.hosts/default
  - shell: test -e $ANSIBLE_HOSTS_FILE && echo 1 || echo 0
    register: has_ansible_hosts_file
  - file: src=$CONFIG_DIR/$DEFAULT_HOSTS dest=$ANSIBLE_HOSTS_FILE state=link
    when_integer: {{has_ansible_hosts_file}} == 0
  - file: src=$CONFIG_DIR/$DEFAULT_HOSTS dest=$CONFIG_DIR/hosts.default state=link
  #### env setter helper
  - shell: test -e $CONFIG_DIR/$ANSIBLE_ENV && echo 1 || echo 0
    register: has_ansible_env
  - template: src=files/ansible/$ANSIBLE_ENV dest=$CONFIG_DIR/$ANSIBLE_ENV mode=0755
    when_integer: ${has_ansible_env.stdout} == 0
  #### link to install
  - shell: test -e $CONFIG_DIR/$INSTALL_LINK && echo 0 || echo 1
    register: need_install_link
  - file: src=$INSTALL_DIR dest=$CONFIG_DIR/$INSTALL_LINK state=link
    when_integer: ${need_install_link.stdout} > 0 and ${has_xdg_config_dir.stdout} > 0
  #### xdg_config_dir/ansible install
  - name: check whether xdg_config_dir exists and is different from CONFIG_DIR:$CONFIG_DIR
    shell: test "${has_xdg_config_dir.stdout}" == 1 -a "x${xdg_config_dir.stdout}" != "x$CONFIG_DIR" -a ! -e "${xdg_config_dir.stdout}/ansible" && echo 1 || echo 0
    register: need_config_link
  - file: src=$CONFIG_DIR dest=${xdg_config_dir.stdout}/ansible state=link
    when_integer: ${need_config_link.stdout} > 0
  - file: src=$CONFIG_DIR/$ANSIBLE_ENV dest=$BIN_DIR/$ANSIBLE_ENV state=link
  ### install git
  - git: repo=$ANSIBLE_GIT dest=$INSTALL_DIR
  ### install ansible-ec2
  - git: repo=https://github.com/pas256/ansible-ec2.git dest=$OPTS_DIR/ansible-ec2
  - file: src=$OPTS_DIR/ansible-ec2 dest=$BINS_DIR/ansible-ec2
  - file: src=$INSTALL_DIR/plugins/inventory/ec2.py dest=$CONFIG_DIR/hosts.ec2
  - file: src=$INSTALL_DIR/plugins/inventory/ec2.ini dest=$CONFIG_DIR/ec2.ini
---
- hosts: all
  user: root
  vars_files:
  - vars/common.vars
  tags:
  - deps
  tasks:
  - include: tasks/ansible.deps.task
    only_if: not $APT_BYPASS
