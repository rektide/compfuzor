---
- hosts: all
  vars:
    TYPE: jellyfin
    INSTANCE: main
    APT_REPO: https://repo.jellyfin.org/debian
    # jellyfin publishes per-stable-codename suites only (bookworm, trixie,
    # ...); there is no forky/unstable suite -- APT_DEFAULT_DISTRIBUTION's
    # forky default 404s here. Track the newest suite jellyfin ships.
    APT_DISTRIBUTION: trixie
  tasks:
    - include: tasks/compfuzor.includes type=etc
