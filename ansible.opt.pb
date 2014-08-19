- hosts: all
  gather_facts: False
  vars:
    TYPE: ansible
    INSTANCE: git
    REPO: https://github.com/ansible/ansible.git
    REPOS:
      ansible-ec2: https://github.com/pas256/ansible-ec2.git
    PKGS:
    - python-jinja2
    - python-yaml
    - python-paramiko
    - python-apt
    - pkg-config # for compfuzor
    ETC_DIRS:
    - hosts
    ETC_FILES:
    - hosts/localhost
    FILES:
    - env.ansible
    LINKS:
      "{{BINS_DIR}}/ansible-ec2": "{{PREFIX_DIR}}/ansible-ec2"
      "{{ETC}}/ec2.ini": "{{DIR}}/plugins/inventory/ec2.ini"
      "{{ETC}}/hosts/ec2": "{{DIR}}/plugins/inventory/ec2.py"
  vars_files:
  - vars/ansible.vars
  tasks:
  - include: tasks/compfuzor.includes
  - name: test for existing ETC/hosts/default
    shell: test -e {{ETC}}/hosts/default; echo $?
    register: has_default
  - name: create a default ETC/hosts/default
    file: src="{{ETC}}/hosts/localhost" dest="{{ETC}}/hosts/default" state=link
    when: has_default.stdout != "0"
