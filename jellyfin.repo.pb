---
- hosts: all
  vars:
    TYPE: jellyfin
    INSTANCE: main
    # deb822 lane (tasks/compfuzor/gen_apt_sources.tasks): APT: renders
    # jellyfin-main.sources + the vendored keyring into ETC, and an
    # install-apt-sources.sh (packages lane) that links both into
    # /etc/apt/sources.list.d and /usr/share/keyrings. Hard precedence:
    # APT: defined -> legacy APT_REPO/APT_DISTRIBUTION vars ignored.
    APT:
      URIs: https://repo.jellyfin.org/debian
      Architectures: [amd64, arm64]
      # jellyfin publishes per-stable-codename suites only (bookworm,
      # trixie, ...); there is no forky/unstable suite -- the forky default
      # 404s here. Track the newest suite jellyfin ships.
      Suites: trixie
      Components: [main]
      # NB the "unstable" component carries daily server builds (2026xxxx)
      # but no jellyfin-ffmpeg8; ffmpeg8 lives in main only and is built
      # against trixie sonames (libbluray2/libvpx9/libx264-164) that
      # forky/sid no longer ship, so the jellyfin METAPACKAGE is not
      # installable on a forky host (hard jellyfin-ffmpeg8 Depends).
      # jellyfin-server from unstable IS installable (deps
      # libfontconfig1/libjemalloc2/adduser/libicu76 all available;
      # Recommends "jellyfin-ffmpeg8 | ffmpeg" lets Debian's ffmpeg satisfy
      # it): apt-get install jellyfin-server jellyfin-web ffmpeg.
    # keyring: vendored files/apt-repos/jellyfin.gpg
    # (4918AABC486CA052358D778D49023CD01DE21A7B)
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
