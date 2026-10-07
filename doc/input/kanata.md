---
type: DeploymentGuide
title: Source-built Kanata and its input services
description: Binary, service, identity, uinput permissions, config-preserving refresh, and the boundary between compiled TCP capability and a listener.
resource: /doc/input/kanata.md
status: stable
generated: { by: model:gpt-6.1-sol, at: 2026-10-07 }
stale_after: 2026-11-07
sources:
  - resource: /kanata.src.pb
    title: Source binary build and copy installation
  - resource: /kanata.srv.pb
    title: Main service, shared identity, and uinput rule
  - resource: /kanata-blueturn.srv.pb
    title: Pedal service
  - resource: /kinata.srv.pb
    title: Declared Kinesis-specific service
  - resource: /design/kanata-source/cutover0.glm53.md
    title: Executed source handoff and verification evidence
---

# Ownership

- [`kanata.src.pb`](/kanata.src.pb) builds Kanata with `tcp_server` and copy-installs a real executable at `/usr/local/bin/kanata`. Copying avoids archive/home traversal under the service sandbox.
- [`kanata.srv.pb`](/kanata.srv.pb) owns canonical `kanata.service`, the persistent `_kanata` account declaration, input-group membership, and `/etc/udev/rules.d/50-kanata-uinput.rules`.
- [`kanata-blueturn.srv.pb`](/kanata-blueturn.srv.pb) and [`kinata.srv.pb`](/kinata.srv.pb) consume the source binary and shared identity. They do not install Debian Kanata or declare the account again.
- The account is a normal persistent system account, not `DynamicUser=`. Sysusers preserves existing IDs; fresh machines allocate ordinary system IDs rather than pinning this host's numbers.

# Current deployment

The [2026-10-07 cutover](/design/kanata-source/cutover0.glm53.md) replaced Debian `1.9.0+ds-1` with source `1.12.1-prerelease-1` from upstream `2f84d17`. Main and BlueTurn run `/usr/local/bin/kanata`; their existing keymap bytes and `/etc/kanata` link targets were preserved. Kinata remains undeployed.

The main config's authored Kinesis exclusion is not yet the live topology. Do not adopt that exclusion by accident while merely updating the source binary or service artifacts.

# Rebuild the binary

Use the local connector when rendering:

```sh
ansible-playbook -i 'localhost,' -c local kanata.src.pb \
  -e REPO_BYPASS=True -e BINS_RUN_BYPASS=True -e APT_INSTALL=present
/usr/local/src/kanata-git/bin/build-rust.sh
sudo /usr/local/src/kanata-git/bin/install-rust.sh
```

This regenerates the build/install scripts while retaining the selected checkout, then explicitly builds and installs. Refresh the source revision deliberately rather than removing the repository bypass accidentally. Installing the binary does not itself restart existing processes; choose a deliberate service restart after validating the revision and deployed configs.

# Refresh service material without replacing keymaps

`KANATA_CONFIG_PRESERVE=True` uses the existing per-file `once` behavior: existing `kanata.kbd` files skip writes, while current units, identity/rule artifacts, install compositions, and link plans regenerate. Without this flag, rendering remains authoritative over the authored config.

```sh
ansible-playbook -i 'localhost,' -c local kanata.srv.pb \
  -e KANATA_CONFIG_PRESERVE=True -e BINS_RUN_BYPASS=True \
  -e SYSTEMD_THUNK_BYPASS=True -e PKGS_BYPASS=True \
  -e APT_BYPASS=True -e GLOBAL_BINS_BYPASS=True
ansible-playbook -i 'localhost,' -c local kanata-blueturn.srv.pb \
  -e KANATA_CONFIG_PRESERVE=True -e BINS_RUN_BYPASS=True \
  -e SYSTEMD_THUNK_BYPASS=True -e PKGS_BYPASS=True \
  -e APT_BYPASS=True -e GLOBAL_BINS_BYPASS=True
```

This prepares durable material; it does not install or start new units. Review and invoke the selected generated install lanes deliberately. Do not run kinata's live deployment merely because its declaration exists. Old undeclared leaves are not automatically pruned; current generated installation compositions omit the Debian apt lane.

# TCP and dial policy

`--port` is compiled in, but the current services have no port argument and retain their network sandbox. Starting a state publisher/listener requires a deliberate endpoint and access-policy change; it no longer requires replacing the Debian build.

Dial action/tier/step policy belongs in [`media-keys.etc.pb`](/media-keys.etc.pb) and/or [`surface-dial.src.pb`](/surface-dial.src.pb), or the dial daemon's own config. Umbriel may consume generated bindings; it is not the authoritative dial configuration or state store. See the [precision-layer inquiry](/design/surface-dial-layers/index.md) for unresolved publisher/provenance and protocol choices.

# Removal and verification cautions

Debian was **removed, not purged**; retained conffile bookkeeping is intentional. A later `apt purge kanata` still runs its account-deletion hook. Do not purge that residue without preserving the source-owned `_kanata` identity.

Startup, parser, executable-path, config-hash, account, and boot-link checks passed at cutover. Physical caps tap-hold feel and pedal reconnect behavior were not exercised by synthetic input; those remain manual checks. The [migration evidence index](/design/kanata-source/index.md) links the build, preparation, preflight, and live result. [Regression coverage](/tests/integration/kanata_source_services.test.py) checks isolated rendering, portable identity, hardening, current installer composition, and the preservation flag without mutating live state.
