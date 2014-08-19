---
- hosts: all
  gather_facts: False
  vars:
    NAME: zsh
    DEFAULT_SHELL: true
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
  - lineinfile: dest=/etc/default/useradd regexp=^SHELL=/bin/zsh$ line=SHELL=/bin/zsh
    when: DEFAULT_SHELL|default(False)
  - shell: executable=/bin/zsh . {{ETC}}/zshrc ; zcompile-all {{ETC}}/z.d {{ETC}}/zfunc.d
