---
- hosts: all
  vars:
    TYPE: fswebcam-loop
    INSTANCE: main
    VAR_DIR: True
    ETC_DIR: True
    SYSTEMD_SERVICE: True
    SYSTEMD_EXEC: "{{BINS_DIR}}/run.sh"
    SYSTEMD_RESTART: always
    SYSTEMD_RESTART_SEC: "2s"
    BINS:
      - name: run.sh
        basedir: var
        exec: |
          fswebcam ${FLAGS} $*
    ENV:
      FLAGS: "{{flags|join(' ')}}"
    flags:
      #- -d /dev/video2
      - -d /dev/video/by-name/c930e
      - --no-banner
      - -r 2304x1536
      - --jpeg 85
      - --no-banner
      - -l 1
      - "--save {{VAR}}/%s.jpg"
      - --palette YUYV
      - --set sharpness=1
      - --set "Focus, Auto"=False
      - --set "Focus (absolute)"=100
  tasks:
    - include: tasks/compfuzor.includes type=srv
