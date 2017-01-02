---
- hosts: all
  vars:
    TYPE: cfssl-ca
    INSTANCE: yoyodyne 
    ETC_FILES:
    - name: cfssl-ca.json
      content: "{{CA_def|to_nice_json}}"
    - name: cfssl-sign.json
      content: "{{SIGN|to_nice_json}}"
    VAR_DIRS:
    - csr
    - cert
    BINS:
    - name: build.sh
      basedir: var
      execs:
      - '# create a ca'
      - 'cfssl gencert -initca ${ETC}/cfssl-ca.json > ca.json.${TIMESTAMP}'
      - 'ln -sf ca.json.${TIMESTAMP} ca.json'
      - 'cat ca.json | cfssljson -bare ca'
      run: '{{ not lookup("fileexists", VAR + "/ca.json") }}'
    - name: regen.sh
      basedir: var
      execs:
      - '# regenerate ca'
      - 'cfssl gencert -renewca -ca ca.pem -ca-key ca-key.pem > ca.json.${TIMESTAMP}'
      - 'ln -sf ca.json.${TIMESTAMP} ca.json'
      - 'cat ca.json | cfssljson -bare ca'
    - name: cert.sh
      basedir: False
      execs:
      - '# generate a key from the ca'
      - '[ -z "$HOSTNAMES" ] && [ -n "${1##*/*}" ] && export HOSTNAMES=$1 && export FILENAME=$VAR/cert/$1'
      - '[ -z "$FILENAME" ] && [ -z "${1##*/*}" ] && export FILENAME=$1'
      - '[ -z "$CONFIG" ] && export CONFIG=${ETC}/cfssl-sign.ca'
      - '[ -z "$CSR" ] && echo "need a csr" 2>&1 && exit 1'
      - '[ -z "$FILENAME" ] && echo "need a filename" 2>&1 && exit 1'
      - 'cfssl gencert ${CA+-ca=$CA} ${CA_KEY+-ca-key=$CA_KEY} ${HOSTNAMES+-hostname=$HOSTNAMES} ${PROFILE+-profile=$PROFILE} ${LOGLEVEL+-loglevel=$LOGLEVEL} $CSR > $VAR/cert/$(basename $FILENAME).json.$TIMESTAMP'
      - 'cat $VAR/cert/$(basename $FILENAME).json.$TIMESTAMP | cfssljson -bare $FILENAME'
    - name: sign.sh
      basedir: False
      execs:
      - '# sign a passed in key'
      - '[ -z "$CA" ]'
      - 'cfssl sign -ca ${ROOT}.pem -ca-key ${ROOT}-key.pem -config ${ETC}/cfssl-sign.json ${VAR}/{{INSTANCE}}.csr > ${VAR}/signed-$(basename $ROOT).json.${TIMESTAMP}'
      - 'cd {{VAR}}'
      - 'cat signed-$(basename $ROOT).json.${TIMESTAMP} | cfssljson -bare signed-$(basename $ROOT)'
    ENV:
      ETC: "{{ETC}}"
      VAR: "{{VAR}}"
      CSR: "{{ETC}}/cfssl-ca.json"
      CA: "{{VAR}}/ca.pem"
      CA_KEY: "{{VAR}}/ca-key.pem"
    CA:
      CN: "{{INSTANCE}}"
      key: "{{key}}"
      names: "{{[name]}}"
      ca: "{{ca}}"
    key:
      algo: ecdsa
      size: 256
    name:
      C: "US"
      L: "Grover's Mill, NJ"
      O: "Yoyodyne"
      OU: "Truncheon bomber division"
    ca:
      pathlen: 2

    SIGN:
      signing:
        profiles: "{{profiles|default({})}}"
        default: "{{ defaults|ignore_empty }}"
      auth_keys: "{{auth_keys}}"
      remotes: "{{remotes}}"
    defaults:
      expiry: "{{expiry|default(CA_EXPIRY)}}"
      usages: "{{usages}}"
      issuer_urls: "{{issuer_urls|default('')}}"
      oscp_url: "{{oscp_url|default('')}}"
      crl_url: "{{crl_url|default('')}}"
      ca_constraint: "{{ca_constraint}}"
      oscp_no_check: "{{oscp_no_check|default('')}}"
      backdate: "{{backdate|default('')}}"
      auth_key: "{{auth_key|default('')}}"
      remote: "{{remote|default('')}}"
      auth_remote: "{{auth_remote|default('')}}"
      not_before: "{{not_before|default('')}}"
      not_after: "{{not_after|default('')}}"
      name_whitelist: "{{name_whitelist|default('')}}"
    expiry: "{{CA_EXPIRY}}"
    usages:
    - digital signature
    - content committment
    - key encipherment
    - key agreement
    - data encipherment
    - cert sign
    - crl sign
    - encipher only
    - decipher only
    - any
    - server auth
    - client auth
    - code signing
    - email protection
    - s/mime
    - ipsec end system
    - ipsec tunnel
    - ipsec user
    - timestamping
    - ocsp signing
    - microsoft sgc
    - netscape sgc
    ca_constraint:
      is_ca: True
      #max_path_len: {{max_path_len|default(2)|int}}
      #max_path_len_zero: True
    auth_keys:
      #ca-auth:
      #  type: standard
      #  key:
    remotes:
      #localhost: "127.0.0.1"

  tasks:
  - include: tasks/compfuzor.includes type=srv
