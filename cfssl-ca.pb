---
- hosts: all
  vars:
    TYPE: cfssl-ca
    INSTANCE: yoyodyne 
    ETC_FILES:
    - name: ca.json
      content: "{{CA|to_nice_json}}"
    - name: sign.json
      content: "{{SIGN|to_nice_json}}"
    VAR_DIRS:
    - csr
    - cert
    BINS:
    - name: build.sh
      exec: |
        # create a ca
        [ -e "$CAR" ] || echo "need a ca request json" 2>&1 && exit 1
        cfssl gencert -initca $CAR > $CA_JSON.$TIMESTAMP
        ln -sf $CA_JSON.$TIMESTAMP $CA_JSON
        (cd $VAR; cat $CA_JSON | cfssljson -bare $CA_FILE)
        echo $CA
      run: '{{ not lookup("fileexists", VAR + "/ca.json") }}'
    - name: regen.sh
      exec: |
        # regenerate ca'
        cfssl gencert -renewca -ca $CA -ca-key $CA_KEY > $CA_JSON.$TIMESTAMP
        ln -sf $CA_KEY.$TIMESTAMP $CA_KEY
        (cd $VAR; cat $CA_JSON | cfssljson -bare $CA_FILE)
        echo $CA
    - name: csr.sh
      basedir: False
      exec: |
        [ -z "$HOSTNAMES" ] && export HOSTNAMES=$1
        [ -z "$HOSTNAMES" ] && [ -n "${1##*/*}" ] && export HOSTNAMES=$1 && export FILENAME=$VAR/cert/$1
        [ -z "$FILENAME" ] && [ -z "${2##*/*}" ] && export FILENAME=$1
        [ -e "$CSR" ] || echo "need a certificate signing request json" 2>&1 && exit 1
        [ -e "$VAR/csr/$FILENAME" ] && echo "csr already exists" 2>&1 && exit 1
        # generate a csr
        is_ca=$(jq -r 'has("ca") // ""')
        cfssl genkey ${is_ca:+-initca=true} $CSR > $FILENAME || echo "CSR $FILENAME already exists"
        cp $FILENAME $VAR/csr/$(basename $FILENAME).$TIMESTAMP
        (cd $VAR/csr; cat $VAR/csr/$(basename $FILENAME).$TIMESTAMP | cfssljson -bare $(basename $FILENAME))
        echo $(basename $FILENAME)
        
        # sign
        $DIR/bin/sign.sh $1 $2
    - name: sign.sh
      basedir: False
      exec: |
        # find thing to sign
        [ ! -e "$1" ] && 1=$VAR/csr/${1%.csr}.csr
        [ ! -e "$1" ] && echo "could not find thing to sign: $1" 2>&1 && exit 1

        # sign a passed in key
        [ -z "$dest" ] && dest=$VAR/cert/$1
        dest=${dest%.pem}
        cfssl sign -ca $CA -ca-key $CA_KEY -config $CSR $1 > $dest.json.$TIMESTAMP
        (cd $VAR; cat $dest.json.$TIMESTAMP | cfssljson -bare $dest)
        echo $dest.pem
    ENV:
      ETC: "{{ETC}}"
      VAR: "{{VAR}}"
      CSR: "{{ETC}}/csr.json"
      CAR: "{{ETC}}/{{CA_FILE}}.json"
      CA: "{{VAR}}/{{CA_FILE}}.pem"
      CA_JSON: "{{VAR}}/{{CA_FILE}}.json"
      CA_KEY: "{{VAR}}/{{CA_FILE}}-key.pem"
      CA_FILE: "{{CA_FILE}}"

    CA_FILE: ca
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
