---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.vars
  vars:
  - DEFAULT_SHELL: true
  tasks:
  - apt: package=zsh state=$APT_INSTALL
  - file: path=$item state=directory
    with_items:
    - /etc/zsh/z.d
    - /etc/zsh/zfunc.d
  - copy: src=files/zsh/$item dest=/etc/zsh/$item
    with_items:
    - zprofile
    - zshrc
    - zlogin
    - zfunc.d/flatten
    - zfunc.d/zcompile-all
    - zfunc.d/zsource-all
    - zfunc.d/zautoload-all
    - z.d/handjam
    - z.d/prompt
  - lineinfile: dest=/etc/default/useradd regexp=^SHELL=/bin/zsh$ line=SHELL=/bin/zsh
    only_if: $DEFAULT_SHELL
  - shell: executable=/bin/zsh zcompile-all /etc/zsh/z.d /etc/zsh/zfunc.d
