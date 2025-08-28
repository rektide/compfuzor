---
- hosts: all
  vars:
    TYPE: it8686
    INSTANCE: git
    REPO: https://github.com/frankcrawford/it87
    ETC_FILES:
      - name: it8686.conf
        content: |
          it87 force_id=0x8686 ignore_resource_conflict=1
    BINS:
      - name: build.sh
        content: |
          make
      - name: install.sh
        content: |
          ln -s $DIR/etc/it8686.conf /etc/modprobe.d/
          make install
      - name: dkms.sh
        content: |
          sudo make dkms_clean
          sudo make dkms
  tasks:
    - import_tasks: tasks/compfuzor.includes
