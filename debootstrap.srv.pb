---
- hosts: all
  vars:
    TYPE: debootstrap
    INSTANCE: main
    BINS_RUN_BYPASS: True
    PKGS_BYPASS: True

    SUITE: "{{ APT_DISTRIBUTION|default(APT_DEFAULT_DISTRIBUTION, true) }}"
    DEBIAN_MIRROR_URI: "{{ APT_MIRROR|default(APT_DEFAULT_MIRROR, true) }}"

    PKGSET:
    PKGSETS:
    PKGS: []

    ETC_FILES:
      - name: pkgs
        content: "{{ lookup('template', 'files/debootstrap/_pkgs') }}"

    ENV:
      NEWROOT: /mnt/newroot
      SUITE: "{{ SUITE }}"
      DEBIAN_MIRROR_URI: "{{ DEBIAN_MIRROR_URI }}"
      APT_ARCH: "{{ APT_ARCH|default(ARCH, true) }}"
      APT_COMPONENTS: "{{ APT_COMPONENTS|default(APT_DEFAULT_COMPONENT, true) }}"
      DEBOOTSTRAP_VARIANT: minbase
      DEBOOTSTRAP_EXCLUDE:
      DEBOOTSTRAP_FOREIGN: "0"
      DEBOOTSTRAP_COPY_RESOLV: "1"
      DEBOOTSTRAP_OPTS:

    BINS:
      - name: debootstrap-newroot
        run: True
        content: |
          # Bootstrap a Debian root filesystem into NEWROOT
          #
          # Usage: debootstrap-newroot [target] [suite] [mirror]
          #   target: new root location (default: $NEWROOT)
          #   suite: Debian release (default: $SUITE)
          #   mirror: Debian mirror URL (default: $DEBIAN_MIRROR_URI)
          #
          # Environment:
          #   APT_ARCH                 target arch (default: host arch)
          #   APT_COMPONENTS           apt components for bootstrap
          #   DEBOOTSTRAP_VARIANT      e.g. minbase
          #   {{ETC}}/pkgs             include list from PKGS/PKGSET/PKGSETS
          #   DEBOOTSTRAP_EXCLUDE      comma-separated package list
          #   DEBOOTSTRAP_FOREIGN      1 for first-stage only
          #   DEBOOTSTRAP_COPY_RESOLV  1 to copy /etc/resolv.conf
          #   DEBOOTSTRAP_OPTS         extra options appended as-is

          TARGET="${1:-${NEWROOT:-/mnt/newroot}}"
          SUITE="${2:-${SUITE:-${APT_DISTRIBUTION:-${APT_DEFAULT_DISTRIBUTION:-bookworm}}}}"
          MIRROR="${3:-${DEBIAN_MIRROR_URI:-${APT_MIRROR:-${APT_DEFAULT_MIRROR:-https://deb.debian.org/debian}}}}"
          ARCH="${APT_ARCH:-$(dpkg --print-architecture 2>/dev/null || true)}"
          COMPONENTS_RAW="${APT_COMPONENTS:-${APT_DEFAULT_COMPONENT:-main}}"
          VARIANT="${DEBOOTSTRAP_VARIANT:-minbase}"
          EXCLUDE_PKGS="${DEBOOTSTRAP_EXCLUDE:-}"
          FOREIGN="${DEBOOTSTRAP_FOREIGN:-0}"
          COPY_RESOLV="${DEBOOTSTRAP_COPY_RESOLV:-1}"
          EXTRA_OPTS="${DEBOOTSTRAP_OPTS:-}"
          PKGS_FILE="${PKGS_FILE:-{{ETC}}/pkgs}"

          COMPONENTS="$(printf '%s' "$COMPONENTS_RAW" | tr -d "[]'" | tr -d '[:space:]')"
          if [ -z "$COMPONENTS" ]; then
            COMPONENTS="main"
          fi

          INCLUDE_PKGS=""
          if [ -f "$PKGS_FILE" ]; then
            INCLUDE_PKGS="$(awk '!/^[[:space:]]*#/ && NF { if (out) out=out "," $0; else out=$0 } END { print out }' "$PKGS_FILE")"
          fi

          echo "Bootstrapping Debian into $TARGET"
          echo "  suite=$SUITE"
          echo "  mirror=$MIRROR"
          echo "  arch=${ARCH:-auto}"
          echo "  variant=$VARIANT"
          echo "  components=$COMPONENTS"
          echo "  include_file=$PKGS_FILE"

          if ! command -v debootstrap >/dev/null 2>&1; then
            echo "Error: debootstrap not found"
            echo "Install it first (for example: apt-get install debootstrap ca-certificates arch-test)"
            exit 1
          fi

          if [ ! -d "$TARGET" ]; then
            mkdir -p "$TARGET"
          fi

          ARCH_FLAG=""
          INCLUDE_FLAG=""
          EXCLUDE_FLAG=""
          FOREIGN_FLAG=""

          if [ -n "$ARCH" ]; then
            ARCH_FLAG="--arch=$ARCH"
          fi
          if [ -n "$INCLUDE_PKGS" ]; then
            INCLUDE_FLAG="--include=$INCLUDE_PKGS"
          fi
          if [ -n "$EXCLUDE_PKGS" ]; then
            EXCLUDE_FLAG="--exclude=$EXCLUDE_PKGS"
          fi
          if [ "$FOREIGN" = "1" ]; then
            FOREIGN_FLAG="--foreign"
          fi

          # shellcheck disable=SC2086
          debootstrap \
            --variant="$VARIANT" \
            --components="$COMPONENTS" \
            ${ARCH_FLAG:+$ARCH_FLAG} \
            ${INCLUDE_FLAG:+$INCLUDE_FLAG} \
            ${EXCLUDE_FLAG:+$EXCLUDE_FLAG} \
            ${FOREIGN_FLAG:+$FOREIGN_FLAG} \
            ${EXTRA_OPTS:+$EXTRA_OPTS} \
            "$SUITE" "$TARGET" "$MIRROR"

          if [ "$COPY_RESOLV" = "1" ] && [ -f /etc/resolv.conf ]; then
            mkdir -p "$TARGET/etc"
            cp /etc/resolv.conf "$TARGET/etc/resolv.conf"
          fi

          if [ "$FOREIGN" = "1" ]; then
            echo "First stage complete (--foreign requested)."
            echo "Run second stage in target arch context:"
            echo "  chroot $TARGET /debootstrap/debootstrap --second-stage"
          else
            echo "Debian root filesystem created in $TARGET"
          fi

      - name: debootstrap-example
        run: True
        content: |
          # Print an end-to-end example for a tmpfs Debian root
          #
          # Usage: debootstrap-example

          cat <<'EOF'
          # 1) Create and prepare tmpfs root (pivot-root playbook)
          mount-tmpfs 3G /mnt/newroot
          prepare-newroot /mnt/newroot oldroot

          # 2) Define desired package sets in this playbook (PKGS/PKGSET/PKGSETS)
          #    then bootstrap Debian in tmpfs (this playbook)
          APT_DISTRIBUTION=bookworm \
          APT_COMPONENTS=main,contrib,non-free-firmware \
          DEBOOTSTRAP_VARIANT=minbase \
          debootstrap-newroot /mnt/newroot

          # 3) Mount virtual filesystems and pivot (pivot-root playbook)
          mount-essential /mnt/newroot
          pivot /mnt/newroot oldroot

          # 4) Optional clean shell in new root
          exec chroot / /bin/bash
          EOF

  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: srv
