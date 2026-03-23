---
- hosts: all
  vars:
    TYPE: debinst-kexec
    INSTANCE: main
    BINS_RUN_BYPASS: True

    PKGSET:
    PKGS:
      - kexec-tools

    SUITE: "{{ APT_DISTRIBUTION|default(APT_DEFAULT_DISTRIBUTION, true) }}"
    DEBIAN_MIRROR_URI: "{{ APT_MIRROR|default(APT_DEFAULT_MIRROR, true) }}"
    INSTALLER_ARCH: "{{ APT_ARCH|default('amd64', true) }}"
    INSTALLER_BASE_URL: "{{ DEBIAN_MIRROR_URI }}/dists/{{ SUITE }}/main/installer-{{ INSTALLER_ARCH }}/current/images/netboot/debian-installer/{{ INSTALLER_ARCH }}"
    INSTALLER_KERNEL: linux
    INSTALLER_INITRD: initrd.gz
    INSTALLER_PRESEED_URL:
    INSTALLER_CMDLINE: "auto=true priority=critical ---"

    GET_URLS:
      - url: "{{ INSTALLER_BASE_URL }}/{{ INSTALLER_KERNEL }}"
        dest: "{{ INSTALLER_KERNEL }}"
      - url: "{{ INSTALLER_BASE_URL }}/{{ INSTALLER_INITRD }}"
        dest: "{{ INSTALLER_INITRD }}"

    ENV:
      SUITE: "{{ SUITE }}"
      DEBIAN_MIRROR_URI: "{{ DEBIAN_MIRROR_URI }}"
      INSTALLER_ARCH: "{{ INSTALLER_ARCH }}"
      INSTALLER_KERNEL: "{{ INSTALLER_KERNEL }}"
      INSTALLER_INITRD: "{{ INSTALLER_INITRD }}"
      INSTALLER_PRESEED_URL: "{{ INSTALLER_PRESEED_URL|default('', true) }}"
      INSTALLER_CMDLINE: "{{ INSTALLER_CMDLINE }}"

    BINS:
      - name: kexec-installer-check.sh
        content: |
          KERNEL="{{SRC}}/${INSTALLER_KERNEL:-linux}"
          INITRD="{{SRC}}/${INSTALLER_INITRD:-initrd.gz}"

          echo "Checking installer artifacts:"
          echo "  kernel: $KERNEL"
          echo "  initrd: $INITRD"

          if [ ! -r "$KERNEL" ] || [ ! -r "$INITRD" ]; then
            echo "Error: missing installer artifacts in {{SRC}}"
            echo "Run this playbook with GET_URLS enabled first."
            exit 1
          fi

          if ! command -v kexec >/dev/null 2>&1; then
            echo "Error: kexec not found (install kexec-tools)"
            exit 1
          fi

          if [ -r /proc/sys/kernel/kexec_load_disabled ]; then
            disabled=$(cat /proc/sys/kernel/kexec_load_disabled)
            if [ "$disabled" != "0" ]; then
              echo "Error: kexec loading disabled (/proc/sys/kernel/kexec_load_disabled=$disabled)"
              exit 1
            fi
          fi

          APPEND="${INSTALLER_CMDLINE:-auto=true priority=critical ---}"
          if [ -n "${INSTALLER_PRESEED_URL:-}" ]; then
            APPEND="auto=true priority=critical url=${INSTALLER_PRESEED_URL} ---"
          fi

          echo "kexec preflight looks good."
          echo "Load command:"
          echo "  kexec -l $KERNEL --initrd=$INITRD --append=\"$APPEND\""
          echo "Execute command:"
          echo "  systemctl kexec   # or: kexec -e"

      - name: kexec-installer-load.sh
        content: |
          KERNEL="{{SRC}}/${INSTALLER_KERNEL:-linux}"
          INITRD="{{SRC}}/${INSTALLER_INITRD:-initrd.gz}"

          if [ ! -r "$KERNEL" ] || [ ! -r "$INITRD" ]; then
            echo "Error: missing installer artifacts in {{SRC}}"
            exit 1
          fi

          APPEND="${INSTALLER_CMDLINE:-auto=true priority=critical ---}"
          if [ -n "${INSTALLER_PRESEED_URL:-}" ]; then
            APPEND="auto=true priority=critical url=${INSTALLER_PRESEED_URL} ---"
          fi

          echo "Loading Debian installer into kexec kernel buffer"
          kexec -l "$KERNEL" --initrd="$INITRD" --append="$APPEND"
          echo "Loaded. To boot now: systemctl kexec"

      - name: kexec-installer-exec.sh
        content: |
          "{{BINS_DIR}}/kexec-installer-load.sh"

          echo "Switching into Debian installer via kexec"
          if command -v systemctl >/dev/null 2>&1; then
            systemctl kexec || kexec -e
          else
            kexec -e
          fi

  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: srv
