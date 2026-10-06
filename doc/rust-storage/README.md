# Rust storage: cache and age-based reclamation

Two independent, user-scoped deployments:

- [`sccache.opt.pb`](/sccache.opt.pb): prebuilt compiler cache, 20G shared cache,
  foreground user daemon, and a dedicated global mise env drop-in.
- [`cargo-sweep.opt.pb`](/cargo-sweep.opt.pb): upstream Cargo artifact sweeping;
  src older than 14 days Mon/Thu 03:00, archive older than 30 days monthly on
  the first at 04:00. Persistent timers are explicit standing deletion approval.

Render with `ansible-playbook -i 'localhost,' -c local <playbook>.pb`.
Both set `BINS_RUN_BYPASS=true`: rendering only generates deployment artifacts.
Read the generated `README.md`, run `bin/build.sh` to install the pinned tool,
preview sweep candidates, then explicitly run `bin/install-user.sh`.
Neither playbook installs root packages, changes main mise/Cargo configuration,
or enables linger. Stop an existing sccache daemon before enabling its service.

Mise installation is confined to the build lane. Runtime executables are direct
deployment symlinks, not per-crate mise wrappers. Sweeps use absolute mise exec
from home for Cargo metadata's Rust environment, with tool/toolchain auto-install
disabled. A missing sweep root is an error. A shared nonblocking flock serializes
these sweeps only; it does **not** protect builds.

## Boundaries and limitations

The sccache size cap is not a Cargo target cap. Incremental compilation is
unchanged unless `SCCACHE_DISABLE_INCREMENTAL=true` explicitly opts into
CARGO_INCREMENTAL=0. Confirm cache effectiveness with real builds and statistics,
not only green service/link status.

Cargo-sweep age uses access time; filesystem atime policy affects eligibility.
Recursive manifests can resolve shared/external target directories through Cargo
metadata: the selected root is a discovery root, **not** a deletion boundary.
Incremental/examples are excluded; hashed dependencies/build outputs may be
deleted even when deployed binaries symlink into them. Un-hashed final binaries
generally remain. There is no active-build lock or support here for nightly's
experimental build-dir, and successful status is not proof of complete cleanup.

## References

- [sccache v0.18.0 debugging](https://github.com/mozilla/sccache/blob/v0.18.0/README.md#debugging):
  foreground server flags; use no CLI arguments alongside SCCACHE_START_SERVER=1.
- [sccache Rust limits](https://github.com/mozilla/sccache/blob/v0.18.0/docs/Rust.md)
  and [local cache](https://github.com/mozilla/sccache/blob/v0.18.0/docs/Local.md).
- [cargo-sweep v0.8.0 CLI](https://github.com/holmgr/cargo-sweep/blob/v0.8.0/src/cli.rs),
  [discovery](https://github.com/holmgr/cargo-sweep/blob/v0.8.0/src/main.rs), and
  [artifact matching](https://github.com/holmgr/cargo-sweep/blob/v0.8.0/src/fingerprint.rs).
- [mise configuration](https://mise.jdx.dev/configuration.html): global conf.d
  fragments preserve the main config; main/project env can override the drop-in.
  [Archived-source trust implementation](https://github.com/jdx/mise/blob/main/src/config/config_file/mod.rs)
  treats discovered global config as trusted, subject to explicit ignored paths.
- [mise sccache registry](https://github.com/jdx/mise/blob/main/registry/sccache.toml)
  advertises the prebuilt aqua backend;
  [cargo backend](https://mise.jdx.dev/dev-tools/backends/cargo.html) defaults to locked installs.
- [`disk-cleanup.opt.pb`](/disk-cleanup.opt.pb): independent interactive emergency
  cleanup tools. These playbooks do not invoke its broader cleanup actions.
