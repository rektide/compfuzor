---
- hosts: all
  vars:
    TYPE: pivot-root
    INSTANCE: main

    # Default configuration
    # NEWROOT: where to mount the tmpfs and pivot to
    # OLDROOT: where to place the old root after pivot (relative to NEWROOT)
    # TMPFS_SIZE: size of tmpfs (default 2G, can use % of RAM)
    # TMPFS_MODE: permissions for tmpfs mount
    ENV:
      NEWROOT: /mnt/newroot
      OLDROOT: oldroot
      TMPFS_SIZE: 2G
      TMPFS_MODE: "0755"

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
