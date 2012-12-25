---
- hosts: all
  user: root
  vars:
  - STATE: installed
  tasks:
  - apt: package=zsh state=$STATE
  - file: path=$item state=directory
    with_items:
    - /etc/zsh/z.d
    - /etc/zsh/zfunc.d
  - copy: src=files/zsh/etc/$item dest=/etc/zsh/$item
    with_items:
    - zprofile
    - zshrc
    - zlogin
    - zfunc.d/flatten
    - zfunc.d/zcompile-all
    - zfunc.d/zsource-all
    - zfunc.d/zautoload-all
    - z.d/handjam
  - shell: executable=/bin/zsh zcompile-all /etc/zsh/z.d /etc/zsh/zfunc.d
