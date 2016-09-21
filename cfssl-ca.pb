---
- hosts: all
  vars:
    TYPE: cfssl-ca
    INSTANCE: yoyodyne 
    ETC_FILES:
    - name: cfssl-ca.json
      content: "{{CA|to_json}}"
    - name: cfssl-sign.json
      content: "{{SIGN|to_json}}"
    VAR_DIR: True
    BINS:
    - name: build.sh
      basedir: var
      execs:
      - "TIMESTAMP=$(date +%y.%m.%d-%T)"
      - "cfssl gencert -initca {{ETC}}/cfssl-ca.json > {{INSTANCE}}.json.${TIMESTAMP}"
      - "cat {{VAR}}/{{INSTANCE}}.json.${TIMESTAMP} | cfssljson -bare {{INSTANCE}}"
      run: True
    - name: sign.sh
      basedir: var
      execs:
      - "TIMESTAMP=$(date +%y.%m.%d-%T)"
      - "ROOT=${1:{{root|default('root')}}}"
      - "cfssl sign -ca ${ROOT}.pem -ca-key ${ROOT}-key.pem -config {{ETC}}/cfssl-sign.json {{INSTANCE}}.csr | cfssljson -bare {{INSTANCE}}-${ROOT}"
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
    CA:
      CN: "{{INSTANCE}}"
      key: "{{key}}"
      names: "{{[name]}}"
      ca: "{{ca}}"
    SIGN:
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
