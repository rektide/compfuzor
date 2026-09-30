---
- hosts: all
  vars:
    TYPE: jellyfin
    INSTANCE: main
    APT_REPO: https://repo.jellyfin.org/debian
    # jellyfin publishes per-stable-codename suites only (bookworm, trixie,
    # ...); there is no forky/unstable suite -- APT_DEFAULT_DISTRIBUTION's
    # forky default 404s here. Track the newest suite jellyfin ships.
    # NB the "unstable" component carries daily server builds (2026xxxx) but
    # no jellyfin-ffmpeg8; ffmpeg8 lives in main only and is built against
    # trixie sonames (libbluray2/libvpx9/libx264-164) that forky/sid no
    # longer ship, so the jellyfin METAPACKAGE is not installable on a forky
    # host (hard jellyfin-ffmpeg8 Depends). jellyfin-server from unstable IS
    # installable (deps libfontconfig1/libjemalloc2/adduser/libicu76 all
    # available; Recommends "jellyfin-ffmpeg8 | ffmpeg" lets Debian's ffmpeg
    # satisfy it): apt-get install jellyfin-server jellyfin-web ffmpeg.
    APT_DISTRIBUTION: trixie
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
