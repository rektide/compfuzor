---
- hosts: all
  vars:
    TYPE: libflam3
    INSTANCE: git
    REPO: https://github.com/scottdraves/flam3
    BINS:
      - name: build.sh
        exec: |
          # https://github.com/scottdraves/flam3/issues/14#issuecomment-331144548
          libtoolize
          automake --add-missing
          autoconf
          ./configure
          make
      - name: install.sh
        become: True
        exec: |

          make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
