---
- hosts: all
  vars:
    REPO: https://github.com/systemd/particleos
    # ParticleOS ships its own mkosi.conf / mkosi.images / mkosi.profiles in
    # the repo — we clone it and wrap the documented mkosi verbs. Do NOT
    # hand-copy upstream config here (the old mkosi.srv.pb did that and rotted).
    # Configure your variant via mkosi.local.conf — see README or local-conf.sh.
    # Requires mkosi (main branch) — install via mkosi.src.pb first.
    PKGS:
      - systemd-container
      - debian-archive-keyring
      - archlinux-keyring
      - fedora-gpg-keys
      - qemu-system-x86
      - ovmf
    BINS:
      - name: build.sh
        basedir: repo
        exec: |
          mkosi -B -f "$@"
      - name: vm.sh
        basedir: repo
        exec: |
          mkosi -f vm "$@"
      - name: update.sh
        basedir: repo
        exec: |
          mkosi -B -ff sysupdate -- update --reboot "$@"
      - name: summary.sh
        basedir: repo
        exec: |
          mkosi summary "$@"
      - name: local-conf.sh
        basedir: repo
        exec: |
          DIST="${1:-debian}"
          shift || true
          PROFILES="${*:-desktop kde}"

          if [ -f mkosi.local.conf ] && [ -z "${FORCE:-}" ]; then
            echo "mkosi.local.conf already exists (set FORCE=1 to overwrite):"
            cat mkosi.local.conf
            exit 0
          fi

          cat > mkosi.local.conf <<EOF
          [Distribution]
          Distribution=$DIST

          [Config]
          Profiles=$PROFILES
          EOF
          echo "wrote mkosi.local.conf:"
          cat mkosi.local.conf
  tasks:
    - import_tasks: tasks/compfuzor.includes
