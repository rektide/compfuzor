---
- hosts: all
  vars:
    TYPE: polychromatic
    INSTANCE: git
    REPO: https://github.com/polychromatic/polychromatic
    BINS:
      - name: build.sh
        excec: |
          
