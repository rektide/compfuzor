---
# polytoken.opt.pb — install the polytoken CLI from dl.polytoken.dev
#
# Compfuzor-native replacement for `curl -fsS https://get.polytoken.dev | bash`.
# The upstream installer: resolves a channel (latest|stable) to a version via
# channels.json, downloads the platform binary + SHA256SUMS from
# dl.polytoken.dev, verifies the sha256 against the <platform>/polytoken
# entry, and installs an 0755 binary on PATH. Mapping:
#   channel resolution  -> PT_CHANNEL (latest|stable), resolved from
#                          channels.json at vars time; -e PT_VERSION=X.Y.Z pins
#   platform detection  -> ARCH (uname -m) -> linux-amd64 / linux-arm64
#   binary + checksums  -> GET_URLS into SRC (+ .url sidecars, so
#                          bin/get-urls.sh re-downloads on demand)
#   sha256 verification -> bin/verify.sh, run every pass; links are
#                          delay: postRun, so nothing goes on PATH unverified
#   PATH install        -> GLOBAL_BINS_DIR (/usr/local/bin); USERMODE=True
#                          lands in ~/.local/bin, the upstream default
# Re-running tracks the channel: a new upstream version changes the GET_URLS
# URLs and get_url replaces the artifacts.
- hosts: all
  vars:
    TYPE: polytoken
    INSTANCE: main
    PT_BASE_URL: https://dl.polytoken.dev
    PT_CHANNEL: latest  # latest | stable
    # Resolve the channel at vars time; override with -e PT_VERSION=X.Y.Z.
    PT_VERSION: "{{ (lookup('url', PT_BASE_URL ~ '/channels.json')|from_json).channels[PT_CHANNEL] }}"
    # ARCH is uname -m; polytoken platforms are linux-amd64 / linux-arm64.
    PT_PLATFORM: "{{ {'x86_64': 'linux-amd64', 'amd64': 'linux-amd64', 'aarch64': 'linux-arm64', 'arm64': 'linux-arm64'}[ARCH] }}"
    GET_URLS:
      - url: "{{PT_BASE_URL}}/{{PT_VERSION}}/{{PT_PLATFORM}}/polytoken"
        dest: polytoken
      - url: "{{PT_BASE_URL}}/{{PT_VERSION}}/SHA256SUMS.{{PT_PLATFORM.split('-')[0]}}"
        dest: SHA256SUMS
    BINS:
      # Upstream's guarantee: the binary must match the SHA256SUMS entry for
      # <platform>/polytoken (the checksums file lists prefixed paths, so
      # extract the hash and check the local file against it).
      - name: verify.sh
        run: True
        basedir: src
        content: |
          expected="$(awk '$2 == "{{PT_PLATFORM}}/polytoken" {print $1}' SHA256SUMS)"
          [ -n "$expected" ] || { echo "no checksum for {{PT_PLATFORM}}/polytoken in SHA256SUMS" >&2; exit 1; }
          echo "$expected  polytoken" | sha256sum -c -
      # Expose the binary: DIR/bin/polytoken -> SRC/polytoken, plus the
      # GLOBAL_BINS_DIR link. delay: postRun links only after verify.sh.
      - link: "{{SRC}}/polytoken"
        global: True
        delay: postRun
    ENV:
      PT_BASE_URL: "{{PT_BASE_URL}}"
      PT_CHANNEL: "{{PT_CHANNEL}}"
      PT_VERSION: "{{PT_VERSION}}"
      PT_PLATFORM: "{{PT_PLATFORM}}"
    README: |
      # polytoken

      CLI installed from {{PT_BASE_URL}} (upstream installer:
      https://get.polytoken.dev).

      - version: {{PT_VERSION}} (channel: {{PT_CHANNEL}}, platform: {{PT_PLATFORM}})
      - artifacts: `{{SRC}}/polytoken` + `{{SRC}}/SHA256SUMS` (`.url` sidecars;
        `bin/get-urls.sh` re-downloads them)
      - verify: `bin/verify.sh` — sha256 against the SHA256SUMS entry
      - on PATH: {{GLOBAL_BINS_DIR}}/polytoken -> {{SRC}}/polytoken

      Re-run the playbook to track the channel; pin with
      `-e PT_VERSION=X.Y.Z` (see the playbook header).
  tasks:
    - import_tasks: tasks/compfuzor.includes
    - name: "polytoken: make downloaded binary executable"
      file:
        path: "{{SRC}}/polytoken"
        mode: "0755"
