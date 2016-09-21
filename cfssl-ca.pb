---
- hosts: all
  vars:
    TYPE: cfssl-ca
    INSTANCE: yoyodyne 
    ETC_FILES:
    - name: cfssl-root.json
      content: "{{csr|to_json}}"
    VAR_DIR: True
    BINS:
    - name: build.sh
      execs:
      - "cd {{VAR}}"
      - "TIMESTAMP=$(date +%y.%m.%d-%T)"
      - "cfssl gencert -initca {{ETC}}/cfssl-root.json > {{INSTANCE}}.json.${TIMESTAMP}"
      - "cat {{VAR}}/{{INSTANCE}}.json.${TIMESTAMP} | cfssljson -bare {{INSTANCE}}"
      run: True
    key:
      algo: ecdsa
      size: 256
    name:
      C: "US"
      L: "Grover's Mill, NJ"
      O: "Yoyodyne"
      OU: "Truncheon bomber division"
    ca:
      expiry: "{{CA_EXPIRY}}"
    csr:
      CN: "{{INSTANCE}}"
      key: "{{key}}"
      names: "{{[name]}}"
      ca: "{{ca}}"
    blahconf:
      signing:
        default:
          usages:
          - digital signature
          - cert sign
          - crl sign
          - signing
          - key encipherment
          expiry: "{{CA_EXPIRY}}"
          is_ca: true
  tasks:
  - include: tasks/compfuzor.includes type=srv
