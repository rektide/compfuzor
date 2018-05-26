- hosts: all
  vars:
    TYPE: usocket
    INSTANCE: git
    REPO: https://github.com/jhs67/usocket
    BINS:
    - name: build.sh
      basedir: True
      run: True
      content: |
        npm install
        sudo npm link -g
  tasks:
  - include: tasks/compfuzor.includes type=src
