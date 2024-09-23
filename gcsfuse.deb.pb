---
- hosts: all
  vars:
    TYPE: gcsfuse
    INSTANCE: 1.0.0
    GET_URLS:
      - "https://github.com/GoogleCloudPlatform/gcsfuse/releases/download/v1.0.0/gcsfuse_1.0.0_amd64.deb"
    BINS:
      - name: install.sh
        run: True
        become: True
        exec: |
          dpkg -i {{DIR}}/src/{{GET_URLS[0]|basename}}
  tasks:
    - include: tasks/compfuzor.includes type=opt
