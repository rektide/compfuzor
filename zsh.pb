---
- hosts: all
  gather_facts: False
  vars:
    NAME: zsh
    DEFAULT_SHELL: True
    PKGS:
    - zsh
    - zsh-doc
    ETC: /etc/zsh
    ETC_DIRS:
    - z.d
    - zfunc.d
    ETC_FILES:
     - zprofile
     - zshrc
     - zlogin
     - zfunc.d/flatten
     - zfunc.d/zcompile-all
     - zfunc.d/zsource-all
     - zfunc.d/zautoload-all
     - z.d/handjam
     - z.d/prompt
  tasks:
  - include: tasks/compfuzor.includes

  # useradd shell
  - lineinfile: dest=/etc/default/useradd regexp="^SHELL=/bin/(?!zsh)" state=absent
    when: DEFAULT_SHELL|default(False)
  - lineinfile: dest=/etc/default/useradd regexp=^SHELL=/bin/zsh$ line=SHELL=/bin/zsh
    when: DEFAULT_SHELL|default(False)

  # adduser shell
  - lineinfile: dest=/etc/adduser.conf regexp="^DSHELL=/bin/(?!zsh)" state=absent
    when: DEFAULT_SHELL|default(False)
  - lineinfile: dest=/etc/adduser.conf regexp=^DSHELL=/bin/zsh$ line=DSHELL=/bin/zsh
    when: DEFAULT_SHELL|default(False)

  # precompile scriptlets
  - shell: executable=/bin/zsh . {{ETC}}/zshrc ; zcompile-all {{ETC}}/z.d {{ETC}}/zfunc.d
