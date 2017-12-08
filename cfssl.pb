---
- hosts: all
  vars:
    TYPE: cfssl
    INSTANCE: yoyodyne 
    ETC_FILES:
    - name: ca.json
      content: "{{CA|to_nice_json}}"
    - name: csr.json
      content: "{{SIGN|to_nice_json}}"
    VAR_DIRS:
    - csr
    - cert
    BINS:
    - name: ca.sh
      exec: |
        # create a ca
        [ ! -e "$CAR" ] && echo "need a ca request json" >&2 && exit 1
        cfssl gencert -initca $CAR > $CA_JSON.$TIMESTAMP
        ln -sf $CA_JSON.$TIMESTAMP $CA_JSON
        (cd $VAR; cat $CA_JSON | cfssljson -bare $CA_FILE)
        echo $(realpath $CA)
      run: '{{ not lookup("fileexists", VAR + "/ca.json") }}'
    - name: regen.sh
      exec: |
        # regenerate ca'
        cfssl gencert -renewca -ca $CA -ca-key $CA_KEY > $CA_JSON.$TIMESTAMP
        ln -sf $CA_KEY.$TIMESTAMP $CA_KEY
        (cd $VAR; cat $CA_JSON | cfssljson -bare $CA_FILE)
        echo $(realpath $CA)
    - name: csr.sh
      basedir: "${VAR}/csr"
      exec: |
        [ -z "$CN" ] && export CN="$1"
        [ -z "$CN" ] && echo "need a common-name which will be used as filename" >&2 && exit 1
        [ ! -e "$CSR" ] && echo "need a certificate signing request json" >&2 && exit 1
        function joinby { local IFS="$1"; shift; echo "$*"; }
        [ -z "$HOSTS" ] && export _HOSTS_J="$(jo -a $*)"

        # generate a csr
        [ -n "${INITCA+x}" ] && INITCA=$(jq -r 'has("ca") // ""' $CSR)
        jq --arg CN "$CN" --argjson HOSTS "$_HOSTS_J" '. + {CN: $CN, hosts: $HOSTS}' $CSR > "$CN.keyconf.$TIMESTAMP"
        cfssl genkey ${INITCA:+-initca=true} "$CN.keyconf.$TIMESTAMP" > "$CN.jsonkey.$TIMESTAMP" || exit 1
        ln -sf $CN.keyconf.$TIMESTAMP $CN.keyconf
        ln -sf $CN.jsonkey.$TIMESTAMP $CN.jsonkey
        cfssljson -bare -f $CN.jsonkey.$TIMESTAMP $CN
        mv "$CN-key.pem" "$CN.key"
        ln -sf $CN.key $CN-key.pem
        echo $(realpath $CN.jsonkey)
    - name: sign.sh
      basedir: "${VAR}/cert"
      exec: |
        [ -z "$CN" ] && export CN="$1"
        [ -z "$CN" ] && echo "need a common-name which will be used as filename" >&2 && exit 1
        if [ "$#" -gte 2 ] ; then
        	function joinby { local IFS="$1"; shift; echo "$*"; }
        	[ -z "$HOSTS" ] && export HOSTS="$(joinby , $*)"
        fi
        [ ! -e "$VAR/csr/$CN.csr" ] && echo "need a csr" >&2 && exit 1

        cfssl sign -ca $CA -ca-key $CA_KEY -config $CSR ${HOSTS:+-hostname "$HOSTS"} "$VAR/csr/$CN.csr" > "$CN.json.$TIMESTAMP"
        ln -sf "$CN.json.$TIMESTAMP" "$CN.json"
        cfssljson -bare -f $CN.json $CN
        echo $(realpath $CN.pem)
    ENV:
      CA_FILE: "{{CA_FILE}}"
      ETC: "{{ETC}}"
      VAR: "{{VAR}}"
      CSR: "{{ETC}}/csr.json"
      CAR: "{{ETC}}/{{CA_FILE}}.request.json"
      CA: "{{VAR}}/{{CA_FILE}}.pem"
      CA_JSON: "{{VAR}}/{{CA_FILE}}.json"
      CA_KEY: "{{VAR}}/{{CA_FILE}}-key.pem"
      TYPE: "{{TYPE}}"
      INSTANCE: "{{INSTANCE}}"

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
