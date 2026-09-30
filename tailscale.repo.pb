---
- hosts: all
  vars:
    TYPE: tailscale
    INSTANCE: main
    # deb822 lane, self-authored stanza (replaces the downloaded
    # {{suite}}.tailscale-keyring.list the old pkg playbook used, which
    # hardcoded its own signed-by and carried no arch declaration).
    # Keyring fetched from upstream's published .noarmor.gpg (binary, no
    # dearmor) under the path tailscale's own tooling expects.
    APT:
      URIs: https://pkgs.tailscale.com/stable/debian
      # tailscale tracks debian codenames; parametric like debian.repo.pb
      Suites: "{{APT_DEFAULT_DISTRIBUTION}}"
      Components: [main]
      # publishes amd64 + arm64 (rpi tailnet peers), no i386
      Architectures: [amd64, arm64]
    APT_TRUSTED: tailscale-archive-keyring
    APT_KEYRING_URL: "https://pkgs.tailscale.com/stable/debian/{{APT_DEFAULT_DISTRIBUTION}}.noarmor.gpg"
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
