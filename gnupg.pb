---
- hosts: all
  sudo: True
  gather_facts: false
  tags:
  - packages
  - root
  vars_files:
  - vars/common.vars
  tasks:
  - apt: pkg=gnupg state=$APT_INSTALL
- hosts: all
  user: rektide
  sudo: False
  tags:
  - user
  gather_facts: false
  vars_files:
  - vars/common.vars
  tasks:
  - file: path=~/.gnupg/private/gnupg/keys state=directory
  - copy: src=$item dest=~/.gnupg/$item
    with_fileglob: private/gnupg/keys/*key
  - shell: gpg --import ~/.gnupg/$item
    with_fileglob: private/gnupg/keys/*key
