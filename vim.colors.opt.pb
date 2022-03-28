---
- hosts: all
  vars:
    TYPE: vim-colors
    INSTANCE: main
    REPOS:
      rainglow: https://github.com/rainglow/vim
      awesome-vim-colorschemes: https://github.com/rafi/awesome-vim-colorschemes
      vim-colorschemes: https://github.com/flazz/vim-colorschemes
    dirs:
    - colors
    - scripts
    - docs
    - autoload
    paths: "{{ SRC + dirs|join(',' ~ SRC) }}"
    ETC_FILES:
    - name: runtimepath.vim
      content: |
        let &runtimepath.=',{{paths}}'
    - name: install.sh
      chdir: repo
      line: source {{ETC}}/runtimepath.vim
    FILES:
    - name: /etc/vim/vimrc
      line: "source {{ETC}}/runtimepath.vim"
      become: true
  tasks:
  - include: tasks/compfuzor.includes type=opt 
