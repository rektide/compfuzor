- hosts: all
  vars:
    TYPE: ansible-py2
    version: main
    INSTANCE: "{{version}}"
    REPO: https://github.com/ansible/ansible.git
    GIT_DIR: "{{SRCS_DIR}}/ansible-main"
    GET_URLS:
      get-pip-2.7.py: "https://bootstrap.pypa.io/pip/2.7/get-pip.py"
      "python-distutils-extra_2.42_all.deb": "http://ftp.us.debian.org/debian/pool/main/p/python-distutils-extra/python-distutils-extra_2.42_all.deb"
    PKGS:
    - python2-dev
    - libapt-pkg-dev
    - python-apt-common
    - python-distutils-extra
    - python-setuptools
    - libpq-dev
    PIPS:
    - jinja2
    - pyyaml
    - paramiko
    #- python-apt
    - psycopg2
    - six
    - netaddr
    - httplib2
    - nose
    - passlib
    - pycrypto
    python: "python2.7"
    ENVS:
      AP2_VERSION: "{{version}}"
    BINS:
    - name: install-pip.sh
      exec: |
        {{python}} get-pip-2.7.py
    - name: install-pips.sh
      exec: |
        for p in {{PIPS|join(' ')}} 
        do
          {{python}} -m pip install $p
        done
    - name: install-version.sh
      basedir: "{{SRV}}"
      exec: |
        if [ ! -d .git ]
        then
            git clone --reference {{GIT_DIR}} {{REPO}} .
        fi
        git fetch -a
        git checkout ${AP2_VERSION:-{{version}}}
        git submodule init
        git submodule update
    # we checkout a specific version into here
    SRV_DIR: true
    ETC_DIRS:
    - hosts
    ETC_FILES:
    - name: hosts/localhost
      content: |
        hosts:
          all:
            localhost
    #LINKS:
    #  "{{BINS_DIR}}/ansible-ec2": "{{DIR}}/ansible-ec2/bin/ansible-ec2"
    #  "{{ETC}}/ec2.ini": "{{DIR}}/contrib/inventory/ec2.ini"
    #  "{{ETC}}/hosts/ec2": "{{DIR}}/contrib/inventory/ec2.py"
  tasks:
  - include: tasks/compfuzor.includes type=src

  #- name: test for existing ETC/hosts/default
  #  shell: test -e "{{ETC}}/hosts/default"; echo $?
  #  register: has_default
  #- name: create a default ETC/hosts/default
  #  file:
  #    src: "{{ETC}}/hosts/localhost"
  #    dest: "{{ETC}}/hosts/default"
  #    state: link
  #  when: has_default.stdout|int != 0

  #- name: test /etc/ansible directory
  #  shell:  test ! -e /etc/ansible -o -L /etc/ansible; echo $?
  #  register: update_ansible
  #- name: symlink in an /etc/ansible directory
  #  file: src="{{ETC}}" dest="/etc/ansible" state=link
  #  when: update_ansible.stdout|int == 0
