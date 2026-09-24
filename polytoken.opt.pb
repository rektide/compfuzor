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
#   binary + checksums  -> GET_URLS fetched straight into DIR/bin (the
#                          deployment payload, not SRC staging), mode 0755.
#                          The spec rows are dumped verbatim to
#                          DIR/etc/get-urls.json; bin/get-urls.sh re-fetches
#                          from that same data contract
#   sha256 verification -> bin/verify.sh, run every pass; the GLOBAL_BINS_DIR
#                          link is delay: postRun, so nothing goes on PATH
#                          unverified
#   PATH install        -> GLOBAL_BINS_DIR (/usr/local/bin); USERMODE=True
#                          lands in ~/.local/bin, the upstream default
#   VFS materialization -> bin/vfs-export.sh walks the shipped polytoken://
#                          VFS (vfs ls/cat) onto disk at DIR/var/vfs
#                          (PT_VFS_DIR); content-gated writes, run every pass
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
    # Where bin/vfs-export.sh materializes the polytoken:// VFS by default.
    PT_VFS_DIR: "{{DIR}}/var/vfs"
    DIRS:
      - var/vfs
    GET_URLS:
      - url: "{{PT_BASE_URL}}/{{PT_VERSION}}/{{PT_PLATFORM}}/polytoken"
        dest: "{{BINS_DIR}}/polytoken"
        mode: "0755"
      - url: "{{PT_BASE_URL}}/{{PT_VERSION}}/SHA256SUMS.{{PT_PLATFORM.split('-')[0]}}"
        dest: "{{BINS_DIR}}/SHA256SUMS"
    BINS:
      # Upstream's guarantee: the binary must match the SHA256SUMS entry for
      # <platform>/polytoken (the checksums file lists prefixed paths, so
      # extract the hash and check the local file against it).
      - name: verify.sh
        run: True
        basedir: bin
        content: |
          expected="$(awk '$2 == "{{PT_PLATFORM}}/polytoken" {print $1}' SHA256SUMS)"
          [ -n "$expected" ] || { echo "no checksum for {{PT_PLATFORM}}/polytoken in SHA256SUMS" >&2; exit 1; }
          echo "$expected  polytoken" | sha256sum -c -
      # Materialize the shipped polytoken:// VFS (facets, resources, subagents,
      # system_prompts, themes) onto disk for easy reading and diffing. Runs
      # every pass so a channel bump re-exports; writes are content-gated
      # (cmp) so unchanged files keep their mtimes, and files dropped
      # upstream are deliberately left in place.
      - name: vfs-export.sh
        run: True
        requires_fs: True
        basedir: bin
        vars: [PT_VFS_DIR]
        content: |
          # Export the polytoken:// VFS onto disk. Usage:
          #   vfs-export.sh [DEST]
          # DEST defaults to $PT_VFS_DIR, then $DIR/var/vfs. Walks
          # `vfs ls` from polytoken:// (trailing / marks a directory) and
          # `vfs cat`s each file. The binary is taken from the verified
          # deployment payload ($DIR/bin/polytoken), falling back to PATH.
          if [ -x "$DIR/bin/polytoken" ]; then
            _pt_bin="$DIR/bin/polytoken"
          elif command -v polytoken >/dev/null 2>&1; then
            _pt_bin="polytoken"
          else
            echo "vfs-export: polytoken not found (looked in \$DIR/bin, PATH)" >&2
            exit 127
          fi
          _pt_dest="${1:-${PT_VFS_DIR:-$DIR/var/vfs}}"
          _pt_written=0
          _pt_kept=0

          vfs_write() {
            local uri="$1" dest="$2" tmp="$2.tmp$$"
            if [ "${_cf_loud:-0}" = 1 ]; then printf 'vfs-export: %s\n' "$uri" >&2; fi
            "$_pt_bin" vfs cat "$uri" >"$tmp"
            if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
              rm -f "$tmp"
              _pt_kept=$((_pt_kept + 1))
            else
              mv -f "$tmp" "$dest"
              _pt_written=$((_pt_written + 1))
            fi
          }

          vfs_export() {
            local uri="$1" dest="$2" entry child listing
            mkdir -p "$dest"
            listing="$("$_pt_bin" vfs ls "$uri")"
            while IFS= read -r entry; do
              [ -n "$entry" ] || continue
              child="${uri%/}/$entry"
              if [ "${entry%/}" != "$entry" ]; then
                vfs_export "$child" "$dest/${entry%/}"
              else
                vfs_write "$child" "$dest/$entry"
              fi
            done <<<"$listing"
          }

          vfs_export "polytoken://" "$_pt_dest"
          printf 'vfs-export: %d written, %d unchanged -> %s\n' \
            "$_pt_written" "$_pt_kept" "$_pt_dest" >&2
      # The payload is already in DIR/bin; expose it on PATH once verified.
      - name: polytoken
        global: True
        src: False
        delay: postRun
    ENV:
      PT_BASE_URL: "{{PT_BASE_URL}}"
      PT_CHANNEL: "{{PT_CHANNEL}}"
      PT_VERSION: "{{PT_VERSION}}"
      PT_PLATFORM: "{{PT_PLATFORM}}"
      PT_VFS_DIR: "{{PT_VFS_DIR}}"
    README: |
      # polytoken

      CLI installed from {{PT_BASE_URL}} (upstream installer:
      https://get.polytoken.dev).

      - version: {{PT_VERSION}} (channel: {{PT_CHANNEL}}, platform: {{PT_PLATFORM}})
      - payload: `{{BINS_DIR}}/polytoken` (0755) + `{{BINS_DIR}}/SHA256SUMS`
        (data contract: `etc/get-urls.json`; `bin/get-urls.sh` re-fetches)
      - verify: `bin/verify.sh` — sha256 against the SHA256SUMS entry
      - on PATH: {{GLOBAL_BINS_DIR}}/polytoken -> {{BINS_DIR}}/polytoken
      - vfs: `bin/vfs-export.sh [dest]` materializes the shipped
        `polytoken://` VFS (vfs ls/cat) to `{{PT_VFS_DIR}}` by default —
        override with `PT_VFS_DIR` or a positional arg; runs every pass,
        content-gated so unchanged files keep their mtimes

      Re-run the playbook to track the channel; pin with
      `-e PT_VERSION=X.Y.Z` (see the playbook header).
  tasks:
    - import_tasks: tasks/compfuzor.includes
