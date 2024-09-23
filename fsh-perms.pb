---
- hosts: all
  tasks:
    - file:
        path: "{{item}}"
        group: adm
        mode: g+rwx
        state: directory
      loop:
        - /etc/opt
        - /opt
        - /srv
        - /usr/local/src
        - /usr/local/bin

