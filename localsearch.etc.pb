---
# LocalSearch (tracker3) indexer containment.
#
# 2026-10-18: localsearch-3 was found running with Debian's packaged schema
# default index-recursive-directories=['$HOME'] -- the ENTIRE home tree,
# ~everything under ~/archive, ~/src, dotdirs. Over 5.3 days it burned 8h18m
# CPU, peaked 8.3G RSS (systemd-oomd killed it), wrote ~MB/s to disk for days,
# and its 4.9G index in ~/.cache/tracker3 was rm'd along with the service
# mask. See the localsearch-3 mask in the user manager: this playbook does NOT
# unmask/re-enable it; it makes re-enabling safe by pinning hard limits
# system-wide.
#
# Mechanism: dconf system database (dconf(7) system-db). /etc/dconf/profile/user
# is created (it did not exist) adding system-db:local ahead of the user db,
# /etc/dconf/db/local.d/00-localsearch sets defaults, and the locks/ fragment
# LOCKS the keys so the user session (GNOME Search settings, gsettings set)
# cannot loosen them. Lifting a limit = edit this playbook + rerun install.sh.
#
# Limits imposed (defaults were: $HOME recursive, 1MB extract reads, no disk
# floor, throttle 0):
#   - index scope: XDG DESKTOP/DOCUMENTS/DOWNLOAD/MUSIC/PICTURES/VIDEOS only;
#     no $HOME recursion, no single-dirs, no removable/optical, no battery
#   - dev-tree chaff ignored (node_modules, target, build, venvs, caches...)
#   - churning files ignored (*.log, *.sqlite*, archives, VM images, core)
#   - fallback rescan at most every 30 days (inotify monitors do the rest)
#   - content extraction capped at 256KB (was 1MB) and allowlisted to
#     txt/md/mdwn; slow-start 60s, throttle 5, pause under 10% free disk
- hosts: all
  vars:
    TYPE: localsearch
    ETC_FILES:
      # dconf profile: creates the user profile (absent before) wiring the
      # system db ahead of per-user settings. Same shape as Debian's shipped
      # profiles (gdm, ibus already exist alongside this).
      - name: dconf/profile-user
        mode: "0644"
        content: |
          user-db:user
          system-db:local
      # compiled into /etc/dconf/db/local by `dconf update`.
      # GOTCHA: section paths are the SCHEMA PATHS, not the schema ids —
      # org.freedesktop.Tracker3.Miner.Files lives at
      # /org/freedesktop/tracker/miner/files/ (lowercase, no 3). Keyfiles
      # under [org/freedesktop/Tracker3/...] are silently unread orphans.
      - name: dconf/local.d/00-localsearch
        mode: "0644"
        content: |
          [org/freedesktop/tracker/miner/files]
          # scope: XDG dirs only. Replaced the catastrophic ['$HOME'].
          index-recursive-directories=['&DESKTOP', '&DOCUMENTS', '&DOWNLOAD', '&MUSIC', '&PICTURES', '&VIDEOS']
          index-single-directories=@as []
          index-removable-devices=false
          index-optical-discs=false
          index-on-battery=false
          index-on-battery-first-time=false
          # cadence: monitors for changes; full crawl fallback monthly, not
          # on every boot; slow start; back off indexing IO; stop at 10% disk
          enable-monitors=true
          crawling-interval=30
          initial-sleep=60
          throttle=5
          low-disk-space-limit=10
          # upstream defaults + dev-tree/vm/archive chaff (setting a key
          # replaces the whole list, so defaults are restated)
          ignored-directories=['po', 'CVS', 'core-dumps', 'lost+found', 'node_modules', 'target', 'build', 'dist', 'out', 'obj', 'vendor', '.venv', 'venv', '__pycache__', '.tox', '.mypy_cache', '.pytest_cache', '.ruff_cache', '.cache', '.cargo', '.rustup', '.gradle', '.m2', '.npm', '.pnpm-store', '.idea', '.vscode', 'cmake-build-debug', 'cmake-build-release']
          ignored-directories-with-content=['.trackerignore', '.git', '.hg', '.nomedia', '.jj', '.svn']
          ignored-files=['*~', '*.o', '*.la', '*.lo', '*.loT', '*.in', '*.m4', '*.rej', '*.gmo', '*.orig', '*.pc', '*.omf', '*.aux', '*.tmp', '*.vmdk', '*.vm*', '*.nvram', '*.part', '*.rcore', '*.lzo', 'autom4te', 'conftest', 'confstat', 'Makefile', 'SCCS', 'ltmain.sh', 'libtool', 'config.status', 'confdefs.h', 'configure', '#*#', '~$*.doc?', '~$*.dot?', '~$*.xls?', '~$*.xlt?', '~$*.xlam', '~$*.ppt?', '~$*.pot?', '~$*.ppam', '~$*.ppsm', '~$*.ppsx', '~$*.vsd?', '~$*.vss?', '~$*.vst?', '*.directory', '*.pyc', '*.pyo', '*.class', '*.elc', '*.so', '*.so.*', '*.a', '*.dll', '*.dylib', '*.wasm', '*.rlib', '*.jar', '*.iso', '*.img', '*.qcow2', '*.vdi', '*.vhdx', '*.swp', '*.swo', '*.log', '*.log.*', '*.sqlite', '*.sqlite3', '*.db', '*.zip', '*.tar', '*.tgz', '*.gz', '*.xz', '*.zst', '*.br', '*.7z', '*.rar', 'core', '*.core']

          [org/freedesktop/tracker/extract]
          # content extraction: fewer bytes read per file, text files only
          max-bytes=262144
          text-allowlist=['*.txt', '*.md', '*.mdwn']
      # lockdown: user session cannot loosen any of the above (schema paths!)
      - name: dconf/local.d/locks/00-localsearch
        mode: "0644"
        content: |
          /org/freedesktop/tracker/miner/files/index-recursive-directories
          /org/freedesktop/tracker/miner/files/index-single-directories
          /org/freedesktop/tracker/miner/files/index-removable-devices
          /org/freedesktop/tracker/miner/files/index-optical-discs
          /org/freedesktop/tracker/miner/files/index-on-battery
          /org/freedesktop/tracker/miner/files/index-on-battery-first-time
          /org/freedesktop/tracker/miner/files/enable-monitors
          /org/freedesktop/tracker/miner/files/crawling-interval
          /org/freedesktop/tracker/miner/files/initial-sleep
          /org/freedesktop/tracker/miner/files/throttle
          /org/freedesktop/tracker/miner/files/low-disk-space-limit
          /org/freedesktop/tracker/miner/files/ignored-directories
          /org/freedesktop/tracker/miner/files/ignored-directories-with-content
          /org/freedesktop/tracker/miner/files/ignored-files
          /org/freedesktop/tracker/miner/files/removable-days-threshold
          /org/freedesktop/tracker/extract/max-bytes
          /org/freedesktop/tracker/extract/text-allowlist
    BINS:
      # Not auto-run (repo convention: privileged steps out of the ansible
      # pass). Apply with: sudo bash /etc/opt/localsearch-main/bin/install.sh
      - name: install.sh
        content: |
          # absolute paths, rendered at generation
          DIR="{{DIR}}"
          set -eu
          # root umask (077 here) would compile /etc/dconf/db/local 0600 and
          # the user session then can't read defaults OR locks -- dconf
          # silently falls back to per-user values, defeating the lockdown
          umask 022
          install -Dm0644 "$DIR/etc/dconf/profile-user" /etc/dconf/profile/user
          install -Dm0644 "$DIR/etc/dconf/local.d/00-localsearch" /etc/dconf/db/local.d/00-localsearch
          install -Dm0644 "$DIR/etc/dconf/local.d/locks/00-localsearch" /etc/dconf/db/local.d/locks/00-localsearch
          dconf update
          chmod 0644 /etc/dconf/db/local
          echo "localsearch limits installed; verify (real schema paths, see gotcha above):"
          echo "  dconf dump /org/freedesktop/tracker/"
          echo "  gsettings get org.freedesktop.Tracker3.Miner.Files index-recursive-directories"
  tasks:
    - import_tasks: tasks/compfuzor.includes
