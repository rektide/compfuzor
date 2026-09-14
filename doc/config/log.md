# Configuration deployment log

## 2026-09-14

### Attributed read-only flow catalog

Repository generation now resolves authoritative deployment identity from
`NAME`, records exact or ambiguous playbook-source evidence, and preserves a
common `contributors[]` reference through BINS, status, and LINKS synthesis.
Native status records have stable IDs; legacy status shorthand receives a
visible `legacy:` identity. Generated compositors retain the contributor union
of their leaves, and compatible duplicate LINKS records union attribution
without weakening relationship conflict checks.

Every deployment compiles safe contributor/action/resource inventory and one
`01-99` indexed file per observed build/install/status invocation under
`etc/compfuzor-runtime`. Existing shell compositors remain authoritative; the
catalog is explicitly read-only. Deployments already carrying the omnibus
runtime expose `compfuzor-catalog.sh`; other deployments emit data without
gaining a Node dependency. Compiled membership is closed against stale files,
while the site layer supports placement-only shadowing and tombstones.

Independent review found and drove correction of catalog materialization,
closed-set selection, cross-flow tombstones, strict array/argument decoding,
filesystem layout override preservation, artifact-derived LINKS attribution,
compositor contributor propagation, and status-ID validation. Focused CONFIG,
Zim, LINKS, systemd, status, tool-version, compiler, catalog, build, lint, and
type checks passed after correction.

CONFIG compilation now also emits its final internal command model directly.
The old emit-then-`_internalize_config_bins()` translation, per-recipe wrappers,
and toggle wrappers are gone. Fixed `config-inputs.sh` preserves explicit
canonical enable/disable administration without restoring wrapper generation.

The Vite+ artifact remains one executable and is now 133.97 kB (31.60 kB gzip)
with catalog inspection included. This entry records repository generation and
tests only; no live `/opt` deployment was rerendered or pruned.

## 2026-09-13

### Omnibus runtime build boundary

The repository build now emits one checked-in executable,
`build/runtime/compfuzor-runtime.mjs`, instead of four bundles with duplicated
CONFIG and delivery code. CONFIG, config-remote, LINKS, and Zim implementations
remain domain-grouped; a minimal root dispatcher selects them through the stable
deployed aliases. Independently complete subsystems contribute identical
artifact records, and the existing name-keyed BINS merge leaves one regular
runtime file in a composed deployment.

The dispatcher preserves CONFIG's `$0` contract by inspecting the lexical
symlink chain before resolving the shared artifact. Fixed actions, chained
context aliases, and arbitrary aliases carrying explicit `--action`/`--context`
therefore still reach CONFIG. Native TypeScript checking now enforces isolated
declarations with explicit exported annotations.

This entry records the repository and integration-test cutover, not a claim that
the live `/opt/zim-main` deployment has already been rerendered.

### Deliberate migration prune

After the Vite+ cutover and clean direct status, the human explicitly requested
pruning. This was a one-time, enumerated migration operation—not automatic
reconciliation behavior.

Removed from the live Zim deployment:

- all 22 inert `.ts` files superseded by the four `.mjs` bundles;
- old `config.sh`, processor/toggle, per-recipe config/status, enable/disable,
  `install-user.sh`, and `zimfw-channel.sh` wrappers;
- the old `bin/processors/` directory;
- legacy `/etc/opt/zim-main/{zim,zim-disabled,zimfw}` fragment trees,
  `zimfw.conf`, and `zim.zsh`;
- two leaked `.config-candidate.*` transaction files;
- the empty `/usr/local/src/zim-main/True` artifact;
- the stale canonical and user links for the removed
  `rektide/zim-systemd-envvar` module.

Removed from Mise only the previously inventoried obsolete dotted-name install
wrappers, disabled systemd installer/helper files, and stale
`mise-user-env.service`. Current `install-user.sh`, Bash blocks, and status tools
remain.

`install-zim.sh` was rerun after removing the stale module so the user assembly,
loaders, and caches reflect the current donor roster. Direct CONFIG assembly,
CONFIG status, Zim activation status, and Mise block status passed. The first
unqualified aggregate Zim status stalled in the unrelated apt-lane reporter;
rerunning with `COMPFUZOR_APTLANE_BYPASS=1` passed, as did Mise aggregate status.

Final deployed source-language counts:

```text
/opt/zim-main/bin:  0 .ts, 0 .py
/opt/mise-main/bin: 0 .ts, 0 .py
```

Exact deletion logs were retained for this session at
`/home/rektide/tmp-opencode/config-prune-20260913.log` and
`/home/rektide/tmp-opencode/config-prune-data-20260913.log`.

### Vite+ packaged runtime cutover

Built the four controller-side deployment inputs with `pnpm build` (Vite+
`vp pack`) and rerendered Zim with the same local, no-package/no-repository
command used below. The render completed with `changed=5`, `failed=0`; it did
not invoke pnpm, npm, apt, downloads, or repository work. The new live runtime
is:

```text
/opt/zim-main/bin/config/command.mjs
/opt/zim-main/bin/config-remote.mjs
/opt/zim-main/bin/links/links.mjs
/opt/zim-main/bin/links.mjs -> /opt/zim-main/bin/links/links.mjs
/opt/zim-main/bin/zim/install.mjs
```

All four files are executable and byte-for-byte match their checked-in
`build/runtime` inputs. The six fixed CONFIG action names now link to
`config/command.mjs`. No Python file is present under `/opt/zim-main/bin`;
Python filter/lookup plugins remained on the Ansible controller.

An initial direct `install-zim.sh` run exposed a package-bootstrap side effect:
`pnpm init` had added a pnpm-only `devEngines.packageManager` constraint, while
the existing block helper invokes npm. npm rejected that constraint and the Zim
installer exited 2 while replacing startup blocks. The generated constraint
was removed with `pnpm pkg delete devEngines`; a clean Vite+ rebuild and a second
`install-zim.sh` run completed and restored both loaders and caches.

Final live checks all exited 0: `config-assemble.sh --check`,
`config-status.sh`, a temporary `config-user-status.sh` symlink (proving manual
`$0` alias inference), `links.mjs status --scope user -q`, `status-zim.sh`, and
aggregate `status.sh`. Both direct and aliased CONFIG status returned 72 rows;
`config-remote.mjs list` returned the two Zim remote targets. Zim cache, loader,
and registry status were all `ok`.

Mise was also rerendered because LINKS is shared. It completed with `changed=0`,
`failed=0`: that deployment does not currently materialize the LINKS manager.
Direct Mise Bash status and aggregate status both exited 0, and its bin tree
contains no `.ts` or `.py` files.

At cutover time, Compfuzor's no-prune policy left these pre-cutover TypeScript
files as inert live residue. They were removed later by the explicit
[migration prune](#deliberate-migration-prune):

```text
/opt/zim-main/bin/config-remote.ts
/opt/zim-main/bin/config/{assembly,cli,command,context,file-state,input-state,inputs,install,invocation,publication,report,status}.ts
/opt/zim-main/bin/links.ts
/opt/zim-main/bin/links/{cli,delivery,links,manifest,operations}.ts
/opt/zim-main/bin/zim/{activation,cli,install}.ts
```

Focused verification covered a clean Vite+ build (including output-directory
cleaning), Vite+ format/lint/type checking, CONFIG command/context/remote and
transaction tests, LINKS delivery/manager/v1/v2/systemd tests, Zim
consumer/donor/demo tests, MCP remote integration, Mise blocks, BINS
composition, and Zim/Mise syntax checks. Vite+ reported four pre-existing
unused-import warnings and no errors.

Deployed the fixed CONFIG command runtime and Zim v2 adapter to `zim-main`, then
materialized Mise's maintained Bash activation blocks. The invoking user was
`rektide`; no system context or donor-admin command was used.

### Preconditions and rendering

`sudo -n true` exited 1, so no sudo path was used. `/opt/zim-main`,
`/etc/opt/zim-main`, `/opt/mise-main`, and `/etc/opt/mise-main` were already
writable by the invoking user. Both playbooks passed syntax checks:

```bash
ansible-playbook zim.opt.pb --syntax-check
ansible-playbook mise.opt.pb --syntax-check
```

The live renders used the required local connector and suppressed package,
repository, download, and automatic bin execution work while retaining
filesystem, config, and bin materialization:

```bash
ansible-playbook -i 'localhost,' -c local zim.opt.pb \
  -e PKGS_BYPASS=True -e APT_BYPASS=True \
  -e REPO_BYPASS=True -e GIT_BYPASS=True \
  -e GET_URLS_BYPASS=True -e BINS_RUN_BYPASS=True

ansible-playbook -i 'localhost,' -c local mise.opt.pb \
  -e PKGS_BYPASS=True -e APT_BYPASS=True \
  -e REPO_BYPASS=True -e GIT_BYPASS=True \
  -e GET_URLS_BYPASS=True -e BINS_RUN_BYPASS=True
```

Zim completed with `failed=0` (`changed=7`); Mise completed with `failed=0`
(`changed=3`). No apt, download, repository, or systemd thunk ran.

### Zim activation

`/opt/zim-main/bin/install.sh --help` reported the ordered children
`install-apt.sh` and `install-zim.sh`. The ordinary aggregate install was then
run with only its unrelated package lane bypassed:

```bash
COMPFUZOR_APTLANE_BYPASS=1 /opt/zim-main/bin/install.sh
```

It seeded 68 consumer input links, assembled `zimrc` and `zimenv`, installed the
isolated `zim-main-zimrc` and `zim-main-zimenv` startup blocks, built both
caches, and linked the registry. Existing startup content remained around the
managed blocks.

Post-install checks:

| Command | Exit/result |
|---|---|
| `/opt/zim-main/bin/config-assemble.sh --check` | 0 |
| `/opt/zim-main/bin/config-assemble.sh --list` | `zimenv`, `zimrc` |
| `/opt/zim-main/bin/config-assemble.sh --stdout zimenv` | 0; 316 bytes; SHA-256 `ced5560b6a084dfcb3db20d474394aa12631fe761261508f63f244a2a0c2a08a` |
| `/opt/zim-main/bin/config-status.sh` | 0 |
| `/opt/zim-main/bin/status-zim.sh` | 0; both loaders and caches `ok` |
| `/opt/zim-main/bin/status.sh` | 0 |

The JSON CONFIG status contained 72 rows: 2 `ready`, 70 `ok`; representations
were 2 assembly outputs and 68 input links. Physical examples:

```text
file  /home/rektide/.config/zsh/zimrc
file  /home/rektide/.config/zsh/zimenv
link  /home/rektide/.config/zsh/zimfw.conf -> /etc/opt/zim-main/zimrc
link  /home/rektide/.config/zsh/zimrc.d/20-environment.conf -> /etc/opt/zim-main/zimrc.d/20-environment.conf
link  /home/rektide/.config/zsh/zimenv.d/20-zim-mise.conf -> /etc/opt/zim-main/zimenv.d/20-zim-mise.conf
```

All six fixed CONFIG files are symlinks to
`/opt/zim-main/bin/config/command.ts`. Both config and Zim specs are version 2,
default to `user`, and expose the declared `canonical,user` and `user` context
sets respectively.

Two concurrent immediate post-install probes transiently observed command
lookup failures (`readlink` missing and `/usr/bin/env` reporting `node: Not a
directory`) while new shells initialized the just-built Zim/Mise environment.
A clean-shell trace showed a valid PATH, ten consecutive fixed-command launches
succeeded, and the final sequential status checks above remained clean. No
persistent drift or malformed activation file was found.

### Mise activation

`/opt/mise-main/bin/install-user.sh --help` reported only
`install-bash-user.sh`; no systemd child was composed. Running:

```bash
/opt/mise-main/bin/install-user.sh
```

applied the `mise-main` managed blocks to `/home/rektide/.bashrc` and
`/home/rektide/.bash_profile` and retained surrounding text. Both direct
`status-mise-bash.sh` and aggregate `status.sh` exited 0. The disabled systemd
environment bridge was not re-enabled or invoked.

### Migration residue observed before the explicit prune

Compfuzor did not prune these legacy files during rendering. They were recorded
for operator review and subsequently removed by the explicit
[migration prune](#deliberate-migration-prune):

```text
/opt/zim-main/bin/config.sh
/opt/zim-main/bin/config-processor.sh
/opt/zim-main/bin/config-toggle.sh
/opt/zim-main/bin/config-zimenv.sh
/opt/zim-main/bin/config-zimrc.sh
/opt/zim-main/bin/status-config.sh
/opt/zim-main/bin/status-config-zimenv.sh
/opt/zim-main/bin/status-config-zimrc.sh
/opt/zim-main/bin/disable.sh
/opt/zim-main/bin/enable.sh
/opt/zim-main/bin/install-user.sh
/opt/zim-main/bin/zimfw-channel.sh
/opt/zim-main/bin/processors/{block-in-file,concat,json-deep-merge}
/opt/mise-main/bin/install-bash.user.sh
/opt/mise-main/bin/install.user.sh
/opt/mise-main/bin/install-service-mise-user-env-user.sh
/opt/mise-main/bin/install-systemd-user.sh
/opt/mise-main/bin/install-unit.sh
/etc/opt/mise-main/mise-user-env.service
```

The Mise service/unit artifacts were residue only: the current compositor did
not reference them. The rendering operation made no prune decision; the later
manual migration did.
