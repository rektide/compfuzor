---
- hosts: all
  vars:
    TYPE: timelapse
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
          rpicam-still ${FLAGS} $*
    ENV:
      FLAGS: "{{flags|join(' ')}}"
    flags:
     - --nopreview
     - --vflip
     - --metering average
     #- --denoise off
     - --denoise cdn_off
     - "--tuning-file {{ETC}}/tuning.json"
     #- --segment {{1000*60*30}}
     - --sharpness 1.1
     - --awb daylight
     - --encoding jpg
     - --quality 85
     - --autofocus-mode manual
     - --lens-position 1
     - --timelapse 1000
     - "--timeout {{1000*60*60*24*365.2}}"
     #- --output 'var/frame_%09d.jpg'
     - --timestamp
     # fixed exposures: --shutter 100000000 --gain 1 --awbgains 1,1
  tasks:
    - include: tasks/compfuzor.includes type=srv
