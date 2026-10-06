# Rust storage: cache and age-based reclamation

Two independent, user-scoped deployments:

- [`sccache.opt.pb`](/sccache.opt.pb): prebuilt compiler cache, 20 GiB shared cache,
  foreground user daemon, and a dedicated global mise env drop-in.
- [`cargo-sweep.opt.pb`](/cargo-sweep.opt.pb): upstream Cargo artifact sweeping;
  src older than 14 days Mon/Thu 03:00, archive older than 30 days monthly on
  the first at 04:00. Persistent timers are explicit standing deletion approval.

Render with `ansible-playbook -i 'localhost,' -c local <playbook>.pb`.
Both set `BINS_RUN_BYPASS=true`: rendering only generates deployment artifacts.
Read the generated `README.md`, run `bin/build.sh` to install the pinned tool,
preview sweep candidates, then explicitly choose the installation lanes.
For sccache, `bin/install-user.sh` also imports a generated Zim shell contributor:
to install only its daemon and mise client link, instead run
`bin/install-systemd-user.sh` followed by `bin/install-links-user.sh`.
For cargo-sweep, `bin/install-user.sh` installs its services/timers.
Neither playbook installs root packages, changes main mise/Cargo configuration,
or enables linger. Stop an existing sccache daemon before enabling its service.

Mise installation is confined to the build lane. Runtime executables are direct
deployment symlinks, not per-crate mise wrappers. Build-time `mise where` and
`mise which --tool` resolve the exact pinned installation/executable without
assuming aqua's archive layout; an executable outside that installation fails.
Sweeps use absolute mise exec
from home for Cargo metadata's Rust environment. Tool auto-install is disabled,
and `exec --no-deps` disables automatic dependency preparation. A preflight
`mise which cargo --tool rust` requires an installed selected Cargo; its absolute
proxy path is passed as CARGO after mise's env evaluation, without resolving a
basename-sensitive rustup symlink. Metadata cannot fall back to ambient/system
Cargo. `RUSTUP_AUTO_INSTALL=0` requires **rustup >=1.28.1** to prevent missing
toolchain installation; install the selected toolchain ahead of time. These
controls are not a network sandbox. Metadata stays in HOME, so mise's global
RUSTUP_TOOLCHAIN can override project toolchain files.
A missing sweep root is an error. A shared blocking flock serializes
these sweeps only; overlapping persistent catch-up runs wait rather than being
skipped. Lock errors propagate. It does **not** protect builds.
Sweep oneshots do not restart automatically on failure; inspect their results
and retry manually or wait for the next timer. The sccache daemon retains its
intended restart-on-failure policy.

## Boundaries and limitations

The sccache size cap is not a Cargo target cap. **sccache cannot cache incremental
Rust compilations.** The deployment renders `ENV: {CARGO_INCREMENTAL: '0'}` and
`ZIM_ENV: [CARGO_INCREMENTAL]`, proposing non-incremental builds through the normal
generated Zim contributor. `ZIM_MODULES: []` activates that existing generation
gate without adding other modules or changing shared infrastructure.
Rendering does **not** install or apply this contribution to the live shell.
Importing it later is explicit; existing non-empty shell values win unless
`COMPFUZOR_ENV_OVERWRITE` matches `CARGO_INCREMENTAL`. The mise drop-in contains
only wrapper/cache settings, not the incremental policy. Evaluate the loss of
incremental builds and confirm cache effectiveness with real builds/statistics,
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
- [sccache size parser](https://github.com/mozilla/sccache/blob/v0.18.0/src/config.rs):
  its `G` suffix multiplies by 1024³, so the configured `20G` means 20 GiB.
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
- [Mise cache inventory](/doc/mise/cache.md): complementary registry/Git cache
  and toolchain accounting, distinct from these compiler-cache and target-artifact policies.
- [Subsystem action runner](/doc/subsys.md#action-runner-_cf_action) and
  [version-manager pins](/doc/subsys.md#build-time-version-manager-pins): existing
  build/install lane conventions. These standalone tool deployments deliberately
  install exact mise specs in their build lane without creating repo-local pins
  or changing a project's Rust selection.
- [Zim contributor synthesis](/tasks/compfuzor/gen_zim.tasks) and
  [env-module don't-stomp policy](/library/filter_plugins/zim_fragment.py):
  `ZIM_ENV` projects the declared incremental setting into a generated module;
  contributor import remains an operator action, separate from inert rendering.
- [rustup environment variables](https://rust-lang.github.io/rustup/environment-variables.html)
  and [rustup 1.28.1 change](https://github.com/rust-lang/rustup/blob/1.28.2/CHANGELOG.md#L23-L28):
  the minimum supported prerequisite for the unattended auto-install guard.
- [cargo_metadata 0.9.1 Cargo selection](https://docs.rs/cargo_metadata/0.9.1/src/cargo_metadata/lib.rs.html):
  metadata honors CARGO before its PATH-based fallback; the sweep wrapper supplies
  the absolute mise-selected proxy while preserving mise's Rust environment.
