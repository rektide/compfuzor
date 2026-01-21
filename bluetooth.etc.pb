---
- hosts: all
  vars:
    PKGS:
      - crudini
    ENV:
      src: "{{DIR}}/etc/main.conf"
      dest: "/etc/bluetooth/main.conf"
    BINS:
      - name: install.sh
        content: |
          cp "$DST" "${DST}.bak.$(date +%s)"
          crudini --merge "$DEST" < "$SRC"
    ETC_FILES:
      - name: main.conf
        content: |
          [General]
          Experimental = true
          PairableTimeout = 30
          #FastConnectable = true
          [BR]
          LinkSupervisionTimeout = 64000
          [AVDTP]
          SessionMode = ertm
          StreamMode = streaming
  tasks:
    - import_tasks: tasks/compfuzor.includes
