# APT sources: deb822 declarations and delivery

`APT:` declares one deb822 source stanza; `APTS:` declares several in one
`<APT_SOURCELIST|TYPE>.sources` file. Keys are apt field names, not a fixed
Compfuzor schema. The defaults from [`vars/apt.yaml`](/vars/apt.yaml) supply
`Types: deb`, `Suites: APT_DEFAULT_DISTRIBUTION` and `Components:
APT_DEFAULT_COMPONENT`; an authored field wins. `APT_DEFAULTS:` can override
the default map. Values can be scalars or space-joined lists; `[]` or `null`
omits a field (for example, `Components: []` for a flat `/` suite). Booleans
emit `yes`/`no`, except `Components: false` also omits that default. The
renderer requires `URIs`, `Suites` and `Types` after defaults are applied.

```yaml
TYPE: nodesource
INSTANCE: 26.x
APT:
  URIs: "https://deb.nodesource.com/node_{{ INSTANCE }}"
  Suites: nodistro
  Architectures: [amd64, arm64]
  By-Hash: yes             # apt field passes through without a new CF var
APT_KEYRING_URL: https://deb.nodesource.com/gpgkey/nodesource.gpg.key
APT_DEARMOR: true
PKGS: [nodejs]
```

For source packages, declare `Types: [deb, deb-src]`. For several independent
stanzas, use `APTS: [{URIs: ..., Suites: ...}, ...]`; `APT` plus `APTS`
concatenates in that order. To change apt preferences, use `APT_PREFS` as a
mapping or list of maps: `Pin` and `Pin-Priority` required, `Package` defaults
to `*`. This writes `<APT_SOURCELIST|TYPE>.pref` under
`/etc/apt/preferences.d`:

```yaml
APT_PREFS:
  Pin: "release n={{ INSTANCE }}"
  Pin-Priority: 600
```

## Keys and trust

`APT_TRUSTED` names a vendored `files/apt-repos/<name>.gpg` (or `.asc` with
`APT_GPG_EXT: asc`). Alternatively `APT_KEYRING_URL` downloads a key; use
`APT_DEARMOR: true` with armored keys to produce binary `.gpg`. If both exist,
the URL takes precedence. A source automatically gets `Signed-By:
/usr/share/keyrings/<name>.gpg` **only** if Compfuzor supplies that keyring;
otherwise apt's system keyrings are used. An authored `Signed-By` field wins
(set it to `null` to omit a derived path). Don't use `Trusted: yes` as a way
to fix a missing key: it disables signature authentication for that source.

An inline `Signed-By: |` ASCII PGP public key is supported on apt 2.4+;
Compfuzor encodes deb822 continuation lines and dot-stuffs blank lines.
Keyring files and the deployment's `etc` directory must remain readable to
apt's `_apt` account. Host apt uses `/etc/apt/sources.list.d`,
`/etc/apt/preferences.d` and `/usr/share/keyrings` by default.

## Delivery and bypasses

During the Ansible filesystem phase, the source, optional preferences and
vendored key are materialized at `ETC` (normally `ETCS_DIR/NAME`, exposed
through `DIR/etc`). With `APT_BYPASS` unset, the render-time
apt tasks download/dearmor URL keys, link the generated files into apt's
system directories, then run a per-source `apt-get update` unless
`APT_UPDATE_BYPASS` is set. This render-time delivery normally needs sudo.

Independently, generation emits `install-apt-sources.sh` in the **packages**
phase. `sudo bash bin/install.sh` runs it before `install-apt.sh`, even on a
repo-only playbook without `PKGS`. It fetches/dearmors URL keys (requires
`curl`, `gpg` if dearmoring), publishes only declared files, then updates the
index unless `COMPFUZOR_APT_UPDATE_BYPASS=1`. The script refuses to replace a
foreign regular file or symlink; it neither prunes old files nor adopts them.
Render-time and install-time links target the same materialized `ETC` path,
not two spellings of it; moving a generated deployment to a host with a
different `ETC` location requires rerendering there.
`COMPFUZOR_APT_SOURCES_BYPASS=1` skips this install-time leaf. Render-time
`APT_BYPASS` does **not** suppress its generation; `APTLANE_BYPASS` only
controls the separate package install/status lane. `PKGS_BYPASS` similarly
only skips render-time package installation.

## Legacy playbooks and migration

If `APT` or `APTS` is **defined**, even if empty (which is an error), its
deb822 path wins. `APT_REPO`, `APT_REPOS`, `APT_LIST_URL`, the old
distribution/component/architecture vars and the string-valued
`APT_PIN`/`APT_PIN_PRIORITY` are ignored, with a warning. `APT_PREFS` is the
new pin declaration; the old `APT_PIN` is never used as a path selector.
When neither `APT` nor `APTS` is defined, the `.list` and old pin tasks run
as before. Key acquisition/naming vars are shared between both paths.

**After converting a deployed playbook:** the old `<name>.list` and previous
pin/key paths are not automatically deleted. Check and remove a stale `.list`
deliberately before `apt-get update`: two declarations for the same repository
can conflict on `Signed-By`. The runtime refuses to overwrite existing
foreign files; this is a manual ownership transition, not reconciliation.

## Cross-references

- [`doc/subsys.md`](/doc/subsys.md) explains the `packages` phase and the
  separate package aptlane.
- [`skill/systemd.md`](/skill/systemd.md) supplies the section-map-over-defaults
  pattern mirrored by `APT` and `APT_DEFAULTS`.
- [`design/apt-deb822/draft1.gpt6sol.md`](/design/apt-deb822/draft1.gpt6sol.md)
  records the compatibility and bootstrap decisions behind this interface.
