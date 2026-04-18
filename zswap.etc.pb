---
- hosts: all
  vars:
    TYPE: zswap
    INSTANCE: main

    ZSWAP_ENABLED: Y
    ZSWAP_COMPRESSOR: lz4
    ZSWAP_ZPOOL: z3fold
    ZSWAP_MAX_POOL_PERCENT: 20
    ZSWAP_ACCEPT_THRESHOLD_PERCENT: 90
    ZSWAP_SAME_FILLED_PAGES_ENABLED: Y
    ZSWAP_EXCLUSIVE_LOADS: Y

    MODULES:
      - zswap

    ETC_FILES:
      - name: zswap-modprobe.conf
        content: |
          options zswap enabled={{ZSWAP_ENABLED}} compressor={{ZSWAP_COMPRESSOR}} zpool={{ZSWAP_ZPOOL}} max_pool_percent={{ZSWAP_MAX_POOL_PERCENT}} accept_threshold_percent={{ZSWAP_ACCEPT_THRESHOLD_PERCENT}} same_filled_pages_enabled={{ZSWAP_SAME_FILLED_PAGES_ENABLED}} exclusive_loads={{ZSWAP_EXCLUSIVE_LOADS}}
      - name: zswap.conf
        dest: zswap.conf
        content: ""

    LINKS:
      - src: "{{ETC}}/zswap-modprobe.conf"
        dest: "/etc/modprobe.d/zswap.conf"

    SYSTEMD_SERVICE: True
    SYSTEMD_TYPE: oneshot
    SYSTEMD_EXEC: "{{DIR}}/bin/apply.sh"
    BINS:
      - name: apply.sh
        content: |
          for param in enabled compressor zpool max_pool_percent accept_threshold_percent same_filled_pages_enabled exclusive_loads; do
            case "$param" in
              enabled) val="{{ZSWAP_ENABLED}}" ;;
              compressor) val="{{ZSWAP_COMPRESSOR}}" ;;
              zpool) val="{{ZSWAP_ZPOOL}}" ;;
              max_pool_percent) val="{{ZSWAP_MAX_POOL_PERCENT}}" ;;
              accept_threshold_percent) val="{{ZSWAP_ACCEPT_THRESHOLD_PERCENT}}" ;;
              same_filled_pages_enabled) val="{{ZSWAP_SAME_FILLED_PAGES_ENABLED}}" ;;
              exclusive_loads) val="{{ZSWAP_EXCLUSIVE_LOADS}}" ;;
            esac
            echo "Setting zswap.$param = $val"
            echo "$val" | sudo tee "/sys/module/zswap/parameters/$param" >/dev/null
          done

    ENV:
      - zswap_enabled
      - zswap_compressor
      - zswap_zpool
      - zswap_max_pool_percent
      - zswap_accept_threshold_percent
    zswap_enabled: "{{ZSWAP_ENABLED}}"
    zswap_compressor: "{{ZSWAP_COMPRESSOR}}"
    zswap_zpool: "{{ZSWAP_ZPOOL}}"
    zswap_max_pool_percent: "{{ZSWAP_MAX_POOL_PERCENT}}"
    zswap_accept_threshold_percent: "{{ZSWAP_ACCEPT_THRESHOLD_PERCENT}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
