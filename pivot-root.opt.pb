---
- hosts: all
  vars:
    BINS_RUN_BYPASS: True

    # Default configuration
    # NEWROOT: where to mount the tmpfs and pivot to
    # OLDROOT: where to place the old root after pivot (relative to NEWROOT)
    # TMPFS_SIZE: size of tmpfs (default 2G, can use % of RAM)
    # TMPFS_MODE: permissions for tmpfs mount
    #
    # Debian net installer options:
    # NETBOOT_* variables are used by fetch-netinstaller.
    ENV:
      NEWROOT: /mnt/newroot
      OLDROOT: oldroot
      TMPFS_SIZE: 2G
      TMPFS_MODE: "0755"
      RSYNC_DIRS: "(/bin /sbin /lib /lib64 /usr /etc /root /home /opt /var)"
      RSYNC_OPTS: "-aHAX --numeric-ids"
      RSYNC_ESTIMATE_OPTS: "--dry-run --stats"
      SSHD_NEW_PORT: "2222"
      SSHD_NEW_UNIT: sshd-newport
      NETBOOT_SUITE: bookworm
      NETBOOT_ARCH: amd64
      NETBOOT_MIRROR: https://deb.debian.org/debian
      NETBOOT_DIR: /installer
      NETBOOT_KERNEL: linux
      NETBOOT_INITRD: initrd.gz
      INSTALLER_PRESEED_URL: ""

    BINS:
      # Mount a tmpfs at the target location for the new root
      - name: mount-tmpfs
        run: True
        content: |
          # Mount a tmpfs filesystem at NEWROOT
          # This will be the target for debootstrap and the new root filesystem
          #
          # Usage: mount-tmpfs [size] [target]
          #   size: tmpfs size (default: $TMPFS_SIZE or 2G)
          #   target: mount point (default: $NEWROOT or /mnt/newroot)

          SIZE="${1:-${TMPFS_SIZE:-2G}}"
          TARGET="${2:-${NEWROOT:-/mnt/newroot}}"
          MODE="${TMPFS_MODE:-0755}"

          echo "Mounting tmpfs (size=$SIZE) at $TARGET"

          # Create mount point if it doesn't exist
          mkdir -p "$TARGET"

          # Check if already mounted
          if mountpoint -q "$TARGET" 2>/dev/null; then
            echo "Warning: $TARGET is already a mount point"
            echo "Current mount:"
            findmnt "$TARGET"
            exit 1
          fi

          # Mount tmpfs
          mount -t tmpfs -o "size=$SIZE,mode=$MODE" tmpfs "$TARGET"

          echo "tmpfs mounted at $TARGET"
          findmnt "$TARGET"

      # Prepare the new root with essential directory structure
      - name: prepare-newroot
        run: True
        content: |
          # Prepare the new root filesystem with essential directories
          # This creates the minimal directory structure needed before debootstrap
          # and ensures the oldroot mount point exists for pivot_root
          #
          # Usage: prepare-newroot [target] [oldroot]
          #   target: new root location (default: $NEWROOT)
          #   oldroot: name for old root dir (default: $OLDROOT)

          TARGET="${1:-${NEWROOT:-/mnt/newroot}}"
          OLDROOT_NAME="${2:-${OLDROOT:-oldroot}}"

          echo "Preparing new root at $TARGET"

          # Verify target is mounted
          if ! mountpoint -q "$TARGET" 2>/dev/null; then
            echo "Error: $TARGET is not a mount point"
            echo "Run mount-tmpfs first"
            exit 1
          fi

          # Create oldroot directory for pivot_root
          # This is where the original root will be accessible after pivot
          mkdir -p "$TARGET/$OLDROOT_NAME"

          # Create minimal directory structure
          # (debootstrap will create most of these, but having them helps)
          for dir in proc sys dev dev/pts dev/shm run tmp; do
            mkdir -p "$TARGET/$dir"
          done

          # Set proper permissions
          chmod 1777 "$TARGET/tmp"
          chmod 755 "$TARGET/proc" "$TARGET/sys" "$TARGET/dev" "$TARGET/run"

          echo "New root prepared at $TARGET"
          echo "Old root will be at $TARGET/$OLDROOT_NAME after pivot"
          ls -la "$TARGET/"

      # Seed the tmpfs root by rsyncing selected directories
      - name: rsync-newroot
        run: True
        content: |
          # Copy a selected set of top-level directories into NEWROOT using rsync
          #
          # Usage: rsync-newroot [target]
          #   target: new root location (default: $NEWROOT)
          #
          # Environment:
          #   RSYNC_DIRS: zsh/bash array expression of source dirs
          #     Example: RSYNC_DIRS='(/bin /sbin /lib /lib64 /usr /etc)'
          #   RSYNC_OPTS: extra rsync options

          TARGET="${1:-${NEWROOT:-/mnt/newroot}}"
          ARRAY_EXPR="${RSYNC_DIRS:-}"
          RSYNC_EXTRA_OPTS="${RSYNC_OPTS:-}"

          if ! command -v rsync >/dev/null 2>&1; then
            echo "Error: rsync not found"
            exit 1
          fi

          if [ -z "$ARRAY_EXPR" ]; then
            echo "Error: RSYNC_DIRS is empty"
            exit 1
          fi

          if [ -z "$RSYNC_EXTRA_OPTS" ]; then
            RSYNC_EXTRA_OPTS="-aHAX --numeric-ids"
          fi

          if ! mountpoint -q "$TARGET" 2>/dev/null; then
            echo "Error: $TARGET must be a mount point"
            echo "Run mount-tmpfs first"
            exit 1
          fi

          dirs=()
          # shellcheck disable=SC2086
          eval "dirs=$ARRAY_EXPR"

          if [ "${#dirs[@]}" -eq 0 ]; then
            echo "Error: RSYNC_DIRS resolved to an empty array"
            exit 1
          fi

          echo "Rsyncing into $TARGET"
          echo "  dirs: ${dirs[*]}"
          echo "  opts: $RSYNC_EXTRA_OPTS"

          for src in "${dirs[@]}"; do
            if [ ! -e "$src" ]; then
              echo "  skip missing: $src"
              continue
            fi

            echo "  rsync $src -> $TARGET/"
            # shellcheck disable=SC2086
            rsync $RSYNC_EXTRA_OPTS "$src" "$TARGET/"
          done

          echo "Rsync seed complete"
          ls -la "$TARGET/"

      # Estimate rsync payload size for current RSYNC_DIRS/RSYNC_OPTS
      - name: size-estimate.src.pb
        content: |
          # Estimate how many bytes rsync-newroot would copy
          #
          # Usage: size-estimate.src.pb [target]
          #   target: destination path for dry-run stats (default: $NEWROOT)
          #
          # Environment:
          #   RSYNC_DIRS: zsh/bash array expression of source dirs
          #   RSYNC_OPTS: base rsync options
          #   RSYNC_ESTIMATE_OPTS: additional options (default: --dry-run --stats)

          TARGET="${1:-${NEWROOT:-/mnt/newroot}}"
          ARRAY_EXPR="${RSYNC_DIRS:-}"
          RSYNC_EXTRA_OPTS="${RSYNC_OPTS:-}"
          RSYNC_DRYRUN_OPTS="${RSYNC_ESTIMATE_OPTS:---dry-run --stats}"

          if ! command -v rsync >/dev/null 2>&1; then
            echo "Error: rsync not found"
            exit 1
          fi

          if [ -z "$ARRAY_EXPR" ]; then
            echo "Error: RSYNC_DIRS is empty"
            exit 1
          fi

          if [ -z "$RSYNC_EXTRA_OPTS" ]; then
            RSYNC_EXTRA_OPTS="-aHAX --numeric-ids"
          fi

          mkdir -p "$TARGET"

          dirs=()
          # shellcheck disable=SC2086
          eval "dirs=$ARRAY_EXPR"

          if [ "${#dirs[@]}" -eq 0 ]; then
            echo "Error: RSYNC_DIRS resolved to an empty array"
            exit 1
          fi

          total_bytes=0

          echo "Estimating rsync payload"
          echo "  target: $TARGET"
          echo "  dirs: ${dirs[*]}"
          echo "  opts: $RSYNC_EXTRA_OPTS $RSYNC_DRYRUN_OPTS"

          for src in "${dirs[@]}"; do
            if [ ! -e "$src" ]; then
              echo "  skip missing: $src"
              continue
            fi

            echo "  estimate: $src"
            # shellcheck disable=SC2086
            stats_out="$(rsync $RSYNC_EXTRA_OPTS $RSYNC_DRYRUN_OPTS "$src" "$TARGET/" 2>/dev/null || true)"

            bytes=""
            while IFS= read -r line; do
              case "$line" in
                "Total file size: "*)
                  bytes="${line#Total file size: }"
                  bytes="${bytes%% bytes*}"
                  bytes="${bytes//,/}"
                  ;;
              esac
            done <<EOF
            $stats_out
            EOF

            if [ -n "$bytes" ]; then
              echo "    total-file-size-bytes: $bytes"
              total_bytes=$((total_bytes + bytes))
            else
              echo "    warning: unable to parse rsync stats for $src"
            fi
          done

          echo ""
          echo "Aggregate estimated payload bytes: $total_bytes"
          if command -v numfmt >/dev/null 2>&1; then
            echo "Aggregate estimated payload human: $(numfmt --to=iec-i --suffix=B "$total_bytes")"
          fi

      # Launch a transient sshd on a different port
      - name: new-sshd
        run: True
        content: |
          # Start a temporary second sshd instance via systemd-run
          # using normal sshd config and only overriding port/pidfile.
          #
          # Usage: new-sshd [port] [unit]
          #   port: ssh port (default: $SSHD_NEW_PORT or 2222)
          #   unit: transient systemd unit name (default: $SSHD_NEW_UNIT)

          PORT="${1:-${SSHD_NEW_PORT:-2222}}"
          UNIT="${2:-${SSHD_NEW_UNIT:-sshd-newport}}"
          SSHD_BIN="$(command -v sshd || true)"

          if [ -z "$SSHD_BIN" ]; then
            echo "Error: sshd not found"
            exit 1
          fi

          if ! command -v systemd-run >/dev/null 2>&1; then
            echo "Error: systemd-run not found"
            exit 1
          fi

          case "$PORT" in
            ''|*[!0-9]*) echo "Error: invalid port '$PORT'"; exit 1 ;;
          esac

          PIDFILE="/run/${UNIT}.pid"

          if systemctl is-active --quiet "$UNIT"; then
            echo "Unit $UNIT is already active"
            systemctl status "$UNIT" --no-pager || true
            exit 0
          fi

          echo "Starting transient sshd unit: $UNIT on port $PORT"
          systemd-run \
            --unit "$UNIT" \
            --collect \
            --property "Type=exec" \
            "$SSHD_BIN" -D -e -f /etc/ssh/sshd_config -o "Port=$PORT" -o "PidFile=$PIDFILE"

          echo "Started. Useful commands:"
          echo "  systemctl status $UNIT"
          echo "  systemctl stop $UNIT"
          echo "  ssh -p $PORT <host>"

      # Mount essential filesystems in the new root (for chroot/pivot)
      - name: mount-essential
        run: True
        content: |
          # Mount essential virtual filesystems in the new root
          # Required before chroot or pivot_root for a functional system
          #
          # Usage: mount-essential [target]
          #   target: new root location (default: $NEWROOT)

          TARGET="${1:-${NEWROOT:-/mnt/newroot}}"

          echo "Mounting essential filesystems in $TARGET"

          # Mount proc if not already mounted
          if ! mountpoint -q "$TARGET/proc" 2>/dev/null; then
            mount -t proc proc "$TARGET/proc"
            echo "  mounted proc"
          fi

          # Mount sysfs if not already mounted
          if ! mountpoint -q "$TARGET/sys" 2>/dev/null; then
            mount -t sysfs sysfs "$TARGET/sys"
            echo "  mounted sysfs"
          fi

          # Mount devtmpfs (or bind mount /dev)
          if ! mountpoint -q "$TARGET/dev" 2>/dev/null; then
            mount --bind /dev "$TARGET/dev"
            echo "  bind-mounted dev"
          fi

          # Mount devpts
          if ! mountpoint -q "$TARGET/dev/pts" 2>/dev/null; then
            mount -t devpts devpts "$TARGET/dev/pts"
            echo "  mounted devpts"
          fi

          # Mount tmpfs on /dev/shm if not already
          if ! mountpoint -q "$TARGET/dev/shm" 2>/dev/null; then
            mount -t tmpfs tmpfs "$TARGET/dev/shm"
            echo "  mounted shm"
          fi

          # Mount run
          if ! mountpoint -q "$TARGET/run" 2>/dev/null; then
            mount -t tmpfs tmpfs "$TARGET/run"
            echo "  mounted run"
          fi

          echo "Essential filesystems mounted"
          findmnt --target "$TARGET" --submounts

      # Download Debian netinstaller kernel/initrd into NEWROOT
      - name: fetch-netinstaller
        run: True
        content: |
          # Fetch Debian installer netboot artifacts into the new root
          #
          # Usage: fetch-netinstaller [target] [suite] [arch]
          #   target: new root location (default: $NEWROOT)
          #   suite: Debian release (default: $NETBOOT_SUITE)
          #   arch: installer arch (default: $NETBOOT_ARCH)

          TARGET="${1:-${NEWROOT:-/mnt/newroot}}"
          SUITE="${2:-${NETBOOT_SUITE:-bookworm}}"
          ARCH="${3:-${NETBOOT_ARCH:-amd64}}"
          MIRROR="${NETBOOT_MIRROR:-https://deb.debian.org/debian}"
          INSTALLER_DIR="${NETBOOT_DIR:-/installer}"
          KERNEL_NAME="${NETBOOT_KERNEL:-linux}"
          INITRD_NAME="${NETBOOT_INITRD:-initrd.gz}"

          BASE_URL="$MIRROR/dists/$SUITE/main/installer-$ARCH/current/images/netboot/debian-installer/$ARCH"
          DEST="$TARGET$INSTALLER_DIR"

          if ! command -v curl >/dev/null 2>&1; then
            echo "Error: curl not found"
            exit 1
          fi

          if ! mountpoint -q "$TARGET" 2>/dev/null; then
            echo "Error: $TARGET must be a mount point"
            echo "Run mount-tmpfs first"
            exit 1
          fi

          mkdir -p "$DEST"

          echo "Fetching netinstaller assets from:"
          echo "  $BASE_URL"

          curl -fL "$BASE_URL/$KERNEL_NAME" -o "$DEST/$KERNEL_NAME"
          curl -fL "$BASE_URL/$INITRD_NAME" -o "$DEST/$INITRD_NAME"

          APPEND="auto=true priority=critical ---"
          if [ -n "${INSTALLER_PRESEED_URL:-}" ]; then
            APPEND="auto=true priority=critical url=${INSTALLER_PRESEED_URL} ---"
          fi

          echo ""
          echo "Netinstaller fetched to:"
          echo "  $DEST/$KERNEL_NAME"
          echo "  $DEST/$INITRD_NAME"
          echo ""
          echo "After pivoting into NEWROOT, boot installer with kexec:"
          echo "  kexec -l $INSTALLER_DIR/$KERNEL_NAME --initrd=$INSTALLER_DIR/$INITRD_NAME --append=\"$APPEND\""
          echo "  systemctl kexec   # or: kexec -e"

      # Perform pivot_root to switch to the new root
      - name: pivot
        run: True
        content: |
          # Pivot root to the new filesystem
          # This switches the root filesystem to NEWROOT and places the old root at OLDROOT
          #
          # WARNING: This is a dangerous operation that changes the system root!
          # Ensure the new root has all necessary files and mounts before running.
          #
          # Usage: pivot [newroot] [oldroot_name]
          #   newroot: new root location (default: $NEWROOT)
          #   oldroot_name: directory name for old root (default: $OLDROOT)
          #
          # After pivot_root:
          #   - / points to what was $NEWROOT
          #   - /$OLDROOT points to the original root filesystem

          TARGET="${1:-${NEWROOT:-/mnt/newroot}}"
          OLDROOT_NAME="${2:-${OLDROOT:-oldroot}}"

          echo "=== PIVOT ROOT ==="
          echo "New root: $TARGET"
          echo "Old root will be at: /$OLDROOT_NAME"
          echo ""

          # Safety checks
          if [ ! -d "$TARGET" ]; then
            echo "Error: Target directory $TARGET does not exist"
            exit 1
          fi

          if ! mountpoint -q "$TARGET" 2>/dev/null; then
            echo "Error: $TARGET must be a mount point"
            exit 1
          fi

          if [ ! -d "$TARGET/$OLDROOT_NAME" ]; then
            echo "Error: Old root mount point $TARGET/$OLDROOT_NAME does not exist"
            echo "Run prepare-newroot first"
            exit 1
          fi

          # Check for essential directories/files
          for check in bin sbin lib; do
            if [ ! -d "$TARGET/$check" ] && [ ! -L "$TARGET/$check" ]; then
              echo "Warning: $TARGET/$check does not exist"
              echo "Has debootstrap been run? The new root may not be bootable."
            fi
          done

          if [ ! -x "$TARGET/bin/sh" ] && [ ! -x "$TARGET/usr/bin/sh" ]; then
            echo "Warning: No shell found in new root"
            echo "The system may not be usable after pivot"
          fi

          echo ""
          echo "Executing pivot_root..."

          # Change to the new root directory
          cd "$TARGET"

          # Perform the pivot
          # pivot_root new_root put_old
          # - new_root: the new root filesystem (must be a mount point)
          # - put_old: where to mount the old root (relative to new_root)
          pivot_root . "$OLDROOT_NAME"

          # Update PATH to use new root
          export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

          echo "pivot_root complete!"
          echo "Current root: /"
          echo "Old root: /$OLDROOT_NAME"
          echo ""
          echo "Next steps:"
          echo "  1. Optionally unmount filesystems under /$OLDROOT_NAME"
          echo "  2. Run cleanup-oldroot to unmount old root mounts"
          echo "  3. Optionally: exec chroot / /bin/sh to get a clean shell"

      # Clean up old root after pivot
      - name: cleanup-oldroot
        run: True
        content: |
          # Clean up and optionally unmount the old root filesystem after pivot
          # Run this AFTER pivot_root to free resources from the old root
          #
          # Usage: cleanup-oldroot [oldroot] [--umount]
          #   oldroot: old root location (default: /$OLDROOT or /oldroot)
          #   --umount: actually unmount (without this, just shows what would be unmounted)

          OLDROOT_PATH="${1:-/${OLDROOT:-oldroot}}"
          DO_UMOUNT=0

          # Parse arguments
          for arg in "$@"; do
            case "$arg" in
              --umount) DO_UMOUNT=1 ;;
            esac
          done

          echo "Old root cleanup: $OLDROOT_PATH"

          if [ ! -d "$OLDROOT_PATH" ]; then
            echo "Error: Old root $OLDROOT_PATH does not exist"
            exit 1
          fi

          # Find all mount points under old root, sorted deepest first
          echo ""
          echo "Mount points under $OLDROOT_PATH:"
          MOUNTS=$(findmnt -R -n -o TARGET "$OLDROOT_PATH" 2>/dev/null | sort -r)

          if [ -z "$MOUNTS" ]; then
            echo "  (none found)"
          else
            echo "$MOUNTS" | while read -r mnt; do
              echo "  $mnt"
            done
          fi

          if [ "$DO_UMOUNT" = "1" ]; then
            echo ""
            echo "Unmounting..."
            echo "$MOUNTS" | while read -r mnt; do
              if [ -n "$mnt" ]; then
                echo "  umount $mnt"
                umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || echo "    failed to unmount $mnt"
              fi
            done
            echo "Cleanup complete"
          else
            echo ""
            echo "Dry run - use --umount to actually unmount"
          fi

      # Undo pivot (for testing/recovery) - switch back to old root
      - name: unpivot
        run: True
        content: |
          # Undo a pivot_root - switch back to the old root
          # This is mainly useful for testing or recovery
          #
          # Usage: unpivot [oldroot]
          #   oldroot: current old root location (default: /$OLDROOT or /oldroot)

          OLDROOT_PATH="${1:-/${OLDROOT:-oldroot}}"

          echo "Switching back to old root at $OLDROOT_PATH"

          if [ ! -d "$OLDROOT_PATH" ]; then
            echo "Error: Old root $OLDROOT_PATH does not exist"
            exit 1
          fi

          if ! mountpoint -q "$OLDROOT_PATH" 2>/dev/null; then
            echo "Error: $OLDROOT_PATH is not a mount point"
            exit 1
          fi

          # We need a place to put the current root
          NEWOLD="oldroot-pivot"
          mkdir -p "$OLDROOT_PATH/$NEWOLD"

          cd "$OLDROOT_PATH"
          pivot_root . "$NEWOLD"

          export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

          echo "Switched back to original root"
          echo "The tmpfs root is now at /$NEWOLD"

      # Show current pivot status and mount information
      - name: status
        run: True
        content: |
          # Show pivot-root status and mount information
          #
          # Usage: status [newroot]

          TARGET="${1:-${NEWROOT:-/mnt/newroot}}"
          OLDROOT_NAME="${OLDROOT:-oldroot}"

          echo "=== Pivot Root Status ==="
          echo ""

          echo "Configuration:"
          echo "  NEWROOT=$TARGET"
          echo "  OLDROOT=$OLDROOT_NAME"
          echo "  TMPFS_SIZE=${TMPFS_SIZE:-2G}"
          echo ""

          echo "Current root filesystem:"
          findmnt / | head -2
          echo ""

          # Check if we appear to be in a pivoted state
          if [ -d "/$OLDROOT_NAME" ] && mountpoint -q "/$OLDROOT_NAME" 2>/dev/null; then
            echo "Status: PIVOTED (old root at /$OLDROOT_NAME)"
            echo ""
            echo "Old root mounts:"
            findmnt -R "/$OLDROOT_NAME" 2>/dev/null || echo "  (none)"
          elif mountpoint -q "$TARGET" 2>/dev/null; then
            echo "Status: TMPFS MOUNTED (not yet pivoted)"
            echo ""
            echo "New root mounts:"
            findmnt -R "$TARGET" 2>/dev/null || echo "  (none)"
            echo ""
            echo "Contents of $TARGET:"
            ls -la "$TARGET/" 2>/dev/null || echo "  (empty or inaccessible)"
          else
            echo "Status: NOT STARTED"
            echo "  $TARGET is not mounted"
          fi

  tasks:
    - import_tasks: tasks/compfuzor.includes
