---
- hosts: all
  vars:
    TYPE: wg
    INSTANCE: main
    GROUP: systemd-network

    listenPort: 51871
    keyFile: "key"
    peers:
    - name: human-name
      key: PEER_human-name_KEY
      ips:
      - 10.0.0.2/32
      endpoint: b.example:51902

    ENV:
      KEY_FILE: "{{keyFile}}"
      LISTEN_PORT: "{{listenPort}}"
    BINS:
    - name: build.sh
      #run: True
      exec: |
        [ ! -f "{{ETC}}/$KEY_FILE" ] && (umask 0007; wg genkey > "{{ETC}}/$KEY_FILE")
        [ ! -f "{{ETC}}/$KEY_FILE.pub" ] && cat {{ETC}}/$KEY_FILE | wg pubkey > "{{ETC}}/$KEY_FILE.pub"
        echo "{\"peers\":$(cat {{ETC}}/peers.json)}" | jinja2 {{SHARE}}/wg.netdev.j2 > {{ETC}}/wg.netdev
        sudo chgrp systemd-network "{{ETC}}/$KEY_FILE"
    LINKS:
    - src: "{{ETC}}/wg.netdev"
      dest: "/etc/systemd/network/90-{{NAME}}.netdev"
    ETC_FILES:
    - name: peers.json
      content: "{{ peers|to_json }}"
    - name: "wg.netdev"
      # stub file that we generate in build.sh
      content: ""
    SHARE_FILES:
    - name: "wg.netdev.j2"
      content: |
        [NetDev]
        Name={{NAME}}
        Kind=wireguard
        Description=WireGuard tunnel {{NAME}}
        {{ 'MTUBytes=' + mtuBytes if mtuBytes|default(False) else '#MTUBytes=' }}
        {{ 'MACAddress=' + macAddress if macAddress|default(False) else '#MACAddress=' }}
         
        [WireGuard]
        ListenPort={{listenPort}}
        PrivateKeyFile={{keyFile|defaultDir(ETC)}}
        {{ 'FirewallMark=' + firewallMark if firewallMark|default(False) else '#FirewallMark=' }}

        {{'{%'}} for peer in peers {{'%}'}}
        [WireGuardPeer]
        PublicKey={{'{{'}}peer.key{{'}}'}}
        PresharedKey={{ETC}}/key.{{'{{'}}peer.name{{'}}'}}.key
        {{'{{'}} 'Endpoint=' + peer.endpoint if peer.endpoint is defined else '#Endpoint=' {{'}}'}}
        {{'{%'}} for ip in peer.ips {{'%}'}}
        AllowedIPs={{'{{'}}ip{{'}}'}}
        {{'{%'}} endfor {{'%}'}}
        {{'{%'}} endfor {{'%}'}}
  tasks:
  - include: tasks/compfuzor.includes type="srv"
