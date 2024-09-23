---
- hosts: all
  vars:
    TYPE: gdrive
    INSTANCE: main
    USERMODE: True
    ENV:
      GDRIVE_CLIENT_ID: onetwo
      GDRIVE_SECRET: threefour
      LABEL: "{{label}}"
      MNT: "{{mnt}}"
    BINS:
      - name: auth.sh
        exec: |
          eval $(opam env)
          google-drive-ocamlfuse -id ${GDRIVE_CLIENT_ID} -secret ${GDRIVE_SECRET} -headless
    # could also jam this into a real env
    SYSTEMD_EXEC_START_PRE: eval $(opam env)
    SYSTEMD_EXEC: google-drive-ocamlfuse -label $LABEL $MNT
    SYSTEMD_EXEC_STOP: fusermount -u $MNT
    SYSTEMD_TYPE: forking

    label: default
    mnt: "~/.mnt/{{NAME}}"
  tasks:
    - include: tasks/compfuzor.includes type=srv
