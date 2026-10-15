---
- hosts: all
  vars:
    TYPE: wireplumber-profile
    INSTANCE: main
    ETC_FILES:
      - name: wireplumber-profile.conf
        content: |
          monitor.alsa.rules = [
            {
              matches = [
                {
                  # WEILIANG 24BIT USB DAC (usb 1-3) shares controller
                  # 0000:02:00.0 with the BS5P-ARC (usb 1-2). Both are
                  # full-speed iso devices; together they exhaust the
                  # controller's isochronous bandwidth, the WEILIANG capture
                  # interface fails usb_set_interface with -ENOSPC every ~5s,
                  # and the erroring node wedges the whole combine_sink driver
                  # group (total silence despite RUNNING states). Pin the card
                  # playback-only so the capture interface never opens.
                  # Restore duplex only after moving it to another controller.
                  device.name = "alsa_card.usb-WEIL_WEILIANG_24BIT_USB-01"
                }
              ]
              actions = {
                update-props = {
                  device.profile = "output:analog-stereo"
                }
              }
            }
          ]
    BINS:
      - name: install-user.sh
        exec: |
          dest="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d"
          mkdir -p $dest
          ln -sf ${ETC}/wireplumber-profile.conf $dest/
    ENV:
      ETC: "{{ETC}}"
      APP: wireplumber
  tasks:
    - import_tasks: tasks/compfuzor.includes
