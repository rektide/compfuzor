- hosts: all
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
    - python-psycopg2
    - python-six
    - python-netaddr
    - python-httplib2
    - python-keyczar
    - pkg-config # for compfuzor
    ETC_DIRS:
    - hosts
    ETC_FILES:
    - hosts/localhost
    LINKS:
      "{{BINS_DIR}}/ansible-ec2": "{{DIR}}/ansible-ec2/bin/ansible-ec2"
      "{{ETC}}/ec2.ini": "{{DIR}}/contrib/inventory/ec2.ini"
      "{{ETC}}/hosts/ec2": "{{DIR}}/contrib/inventory/ec2.py"
  vars_files:
  - vars/ansible.vars
  tasks:
  - include: tasks/compfuzor.includes type=src

  - name: test for existing ETC/hosts/default
    shell: test -e "{{ETC}}/hosts/default"; echo $?
    register: has_default
  - name: create a default ETC/hosts/default
    file: src="{{ETC}}/hosts/localhost" dest="{{ETC}}/hosts/default" state=link
    when: has_default.stdout|int != 0

  - name: test /etc/ansible directory
    shell:  test ! -e /etc/ansible -o -L /etc/ansible; echo $?
    register: update_ansible
  - name: symlink in an /etc/ansible directory
    file: src="{{ETC}}" dest="/etc/ansible" state=link
    when: update_ansible.stdout|int == 0
