---
# vintage of llvm that still had -ast-print-xml
# http://lists.cs.uiuc.edu/pipermail/cfe-dev/2011-March/013870.html
- hosts: all
  tags:
  - source
  gather_facts: False
  vars:
    INSTANCE: git
    SOURCE_INSTANCE: git
    MIDFIX: pretty-ast
    DEST: "{{ SRCS_DIR }}/{{ item }}-{{ MIDFIX }}-{{ INSTANCE }}"
    OUT_OF:  "{{ SRCS_DIR }}/{{ item }}-{{ SOURCE_INSTANCE }}"
    FOR:
    - clang
    - llvm
    VERSIONS:
      llvm: 127140
      clang: 127139
    DIR_BYPASS: True
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  # DIY: - include: src-llvm.pb
  - file: path={{ DEST }} state=directory
    with_items: $FOR
  - shell: cp -aur {{ OUT_OF }}/.git {{ DEST }}/.git
    with_items: $FOR
  - file: path={{ DEST }}/.git/objects state=absent
    with_items: $FOR
  - file: src={{ OUT_OF }}/.git/objects dest={{ DEST }}/.git/objects state=link
    with_items: $FOR
  - shell: chdir={{ DEST }} git checkout master -f
    with_items: $FOR
  - shell: chdir={{ DEST }} git reset --hard HEAD
    with_items: $FOR
  - shell: chdir={{ DEST }} git log --grep='.*{{ VERSIONS[item] }}.*'|head -n1|awk '{ print $2 }'|tee ./.git/refs/heads/{{ MIDFIX }}
    with_items: $FOR
  - shell: chdir={{ DEST }} git checkout {{ MIDFIX }}
    with_items: $FOR
  - shell: chdir={{ DEST }} git reset --hard HEAD
    with_items: $FOR
  - copy: src=files/llvm/build-pretty-ast.patch dest={{ SRCS_DIR }}/llvm-{{ MIDFIX }}-{{ INSTANCE }}/build-pretty-ast.patch
  - file: src={{ SRCS_DIR }}/clang-{{ MIDFIX }}-{{ INSTANCE }} dest={{ SRCS_DIR }}/llvm-{{ MIDFIX }}-{{ INSTANCE }}/tools/clang state=link
  - shell: chdir={{ SRCS_DIR }}/llvm-{{ MIDFIX }}-{{ INSTANCE }}/lib/ExecutionEngine/JIT patch < ../../../build-pretty-ast.patch
