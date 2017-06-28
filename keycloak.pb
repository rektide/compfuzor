---
- hosts: all
  vars:
    TYPE: keycloak
    INSTANCE: git
    REPO: https://github.com/keycloak/keycloak
    BINS:
    - name: build.sh
      run: True
      execs:
      - mvn install -DskipTests -Pdistribution
    SYSTEMD_SERVICE: False
  tasks:
  - include: tasks/compfuzor.includes type=src
