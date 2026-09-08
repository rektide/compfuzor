---
type: Reference
title: watchman socket discovery & interop requirements
description: Catalog of every server/client socket-discovery mechanism in facebook/watchman C++ (v2026.08.17.00), with file:line refs, for the watchwoman drop-in replacement.
resource: https://github.com/rektide/compfuzor/blob/main/.design/watchman-interop/watchman-interop.glm53.md
tags: [watchman, watchwoman, interop, sockets]
status: stable
generated: { by: agent:glm53, at: 2026-08-30 }
verified: { by: unverified, at: never }
sources:
  - id: watchman-src
    title: facebook/watchman checkout v2026.08.17.00-3-g20966cdb7
    resource: file:///home/rektide/archive/facebook/watchman
    last_modified: 2026-08-17
  - id: watchman-upstream-tags
    title: upstream GitHub tags v2.9.9 / v3.0.0 / v4.9.0 (raw files)
    resource: https://github.com/facebook/watchman
---

> Model-suffix note: the authoring model could not self-determine its exact
> version from the environment. `glm53` is the best inference (GLM 5.x via the
> Z.AI plan used by this harness's default subagents). Treat the suffix as
> approximate; the content is source-verified.

Research question: what must a drop-in replacement daemon (watchwoman)
replicate on the *discovery* layer so every real watchman client keeps
working? Prior assumption: "compat symlinks at one or two paths". Finding:
the compat surface is **per-build-family**, and the single most-hit mechanism
is not a path at all — it is the `watchman get-sockname` subprocess protocol.

All `file:line` references are against the local getdeps checkout
`/home/rektide/archive/facebook/watchman` (tag `v2026.08.17.00-3-g20966cdb7`,
"current" below) unless prefixed with an upstream tag like `v4.9.0:`.

---

## 1. Discovery chain — SERVER side

The server never "discovers" anything at runtime beyond one computation done
at CLI-parse time. Both the CLI and the daemon share the same binary and the
same `flags.unix_sock_name` string.

### 1.1 Option parsing

| option | short | target | ref |
|---|---|---|---|
| `--sockname=PATH` | `-U` | `flags.unix_sock_name` (deprecated alias) | `watchman/Options.cpp:70-78` |
| `--unix-listener-path=PATH` | `-u` | `flags.unix_sock_name` | `watchman/Options.cpp:86-97` |
| `--statefile=PATH` | | `flags.watchman_state_file` | `watchman/Options.cpp:133-139` |
| `--logfile=PATH` (`-` = stdout) | `-o` | `logging::log_name` | `watchman/Options.cpp:98-104` |
| `--pidfile=PATH` | | `flags.pid_file` | `watchman/Options.cpp:112-118` |
| `--test-state-dir=DIR` | | `flags.test_state_dir` (test-only) | `watchman/Options.cpp:198-206` |
| `--named-pipe-path=PATH` | | `flags.named_pipe_path` (win32) | `watchman/Options.cpp:79-85` |

All default-empty (`watchman/Options.h:24-29`). Anything passed here wins over
every default. Daemon-class options are echoed into `daemon_argv` so a spawned
server inherits them (`watchman/Options.cpp:406-409`).

### 1.2 Default computation

`parse_cmdline` → `setup_sock_name()` (`watchman/main.cpp:739-759`, body at
`617-695`):

1. `user = computeUserName()` — `$USER` → `$LOGNAME` → `getpwuid(getuid())`
   (`watchman/UserDir.cpp:91-135`).
2. TMPDIR is snapshotted *now* in case the env changes later
   (`watchman/main.cpp:627-629`; `getTemporaryDirectory()` cached at
   `watchman/UserDir.cpp:172-175`, value = `$TMPDIR` → `$TMP` → `/tmp`,
   `watchman/UserDir.cpp:77-87`).
3. `compute_file_name(flags.unix_sock_name, user, "sock", "sockname")`
   (`watchman/main.cpp:648`).
4. Same for `state` (`main.cpp:650-651`) and `log` (`main.cpp:689-694`).
   The pidfile is computed lazily, only in server context
   (`main.cpp:73-76`, `480-481`).
5. Log precedence: `--logfile` > config key `log_dir` →
   `<log_dir>/<user>/log` (dir created 0755, `main.cpp:657-684`,
   `watchman/PathUtils.cpp:186-209`) > default `<state_dir>/log`
   (`main.cpp:653-694`).

`compute_file_name` (`watchman/PathUtils.cpp:211-253`): if the string is
empty, it is `"<state_dir>/<suffix>"` where `<state_dir>` comes from
`computeWatchmanStateDirectory(user)` — and computing it has the **side
effect of creating and chmod-ing the state dir** (see §4). Explicit values
are only validated to be absolute (fatal otherwise; logfile `-` exempt).

### 1.3 `computeWatchmanStateDirectory` — the precedence chain

`watchman/UserDir.cpp:195-219`, in order:

1. `--test-state-dir=DIR` (CLI) → `<DIR>/<user>-state` (`:196-198`)
2. env `WATCHMAN_TEST_STATE_DIR` → **used verbatim as the whole state dir**
   (`:200-203`)
3. Windows → `%LOCALAPPDATA%/watchman` (`:205-206`)
4. build with `WATCHMAN_USE_XDG_STATE_HOME` →
   `$XDG_STATE_HOME/watchman/<user>-state`, where `XDG_STATE_HOME` defaults
   to `$HOME/.local/state` (`:209-210`, `:177-193`)
5. build with `WATCHMAN_STATE_DIR` → `WATCHMAN_STATE_DIR/<user>-state`
   (`:211-212`)
6. otherwise → `$TMPDIR|$TMP|/tmp/<user>-state` (`:213-214`)

`$HOME` itself is `getpwuid()->pw_dir` first, `$HOME` env second
(`watchman/UserDir.cpp:137-165`).

### 1.4 What the macros are

- CMake (current): `WATCHMAN_STATE_DIR` defaults to
  `"${CMAKE_INSTALL_PREFIX}/var/run/watchman"`
  (`CMakeLists.txt:165-167`), i.e. **`/usr/local/var/run/watchman` for the
  default configure prefix `/usr/local`**; emitted to `config.h` at
  `CMakeLists.txt:198-200`. `WATCHMAN_USE_XDG_STATE_HOME` is a default-OFF
  option (`CMakeLists.txt:173-177`, `:207-209`).
- Autotools (≤ v4.9.0): same shape, `WATCHMAN_STATE_DIR="$xprefix/var/run/watchman"`
  (`v4.9.0:configure.ac`, `--enable-statedir=PATH` to override, `no` disables
  the macro entirely → TMPDIR fallback).
- Meta-internal getdeps: `/opt/facebook/watchman/var/run/watchman`
  (`build/fbcode_builder/manifests/watchman:42`).
- **This host's builds** (getdeps install tree
  `/usr/local/src/watchman-git/watchman`):
  - installed July build (`/usr/local/bin/watchman` → `bin/watchman`,
    version `20260708.093114.0`): compiled-in
    `/usr/local/src/watchman-git/watchman/var/run/watchman` (verified via
    `strings`), so its default sock is
    `/usr/local/src/watchman-git/watchman/var/run/watchman/<user>-state/sock`.
  - August rebuild in `build/`: `WATCHMAN_STATE_DIR=/usr/local/var/run/watchman`,
    `WATCHMAN_USE_XDG_STATE_HOME=OFF` (`build/CMakeCache.txt`,
    `build/watchman/config.h:4`). `/usr/local/var/run/watchman` does not
    currently exist on this host.

So the "state dir" is a *per-build-family* constant. Two different watchman
binaries on one box can disagree about the default socket path. That is the
core reason "one or two compat symlinks" is fragile: the symlink set must
mirror every CLI build family that real clients might exec.

### 1.5 Binding

`w_start_listener` → `get_listener_unix_domain_socket(path)`
(`watchman/listener.cpp:66-168`, called at `:495`):

- rejects `strlen(path) >= sizeof(sun_path)-1` (§3) (`:73-77`)
- `unlink(path)` **before** `bind()` — the server itself clears stale socket
  files (`:87-88`)
- `chmod(path, cfg_get_perms("sock_access", write=true, execute=false))` —
  default `0600` (`:68-69`, `:97-100`; defaults in
  `watchman/WatchmanConfig.cpp:369-386`)
- optional group sharing: `sock_group` (chown gid + verify, `:121-159`,
  dir-level at `watchman/PathUtils.cpp:89-106`) and Linux-only
  `secondary_sock_group` POSIX ACL (`:101-119`)
- `listen(backlog=200)` (`:162`)

No abstract-namespace sockets anywhere in the tree; always a filesystem path.
`--inetd` uses `dup(STDIN_FILENO)` as the listener fd
(`watchman/main.cpp:134-137`, `watchman/listener.cpp:50-62`, used at
`:491-493`). There is no `LISTEN_FDS`/fd-3 systemd protocol support
upstream — socket-activated deployments must hand the socket over as stdin
(`Standard=socket`) and pass `--inetd`, or handle fd 3 themselves.

### 1.6 Environment variables the C++ side actually reads

Full inventory (`rg getenv` over non-test C++): `WATCHMAN_TEST_STATE_DIR`
(`UserDir.cpp:200`), `WATCHMAN_NO_SPAWN` (`main.cpp:754`),
`WATCHMAN_CONFIG_FILE` (`WatchmanConfig.cpp:28`; compiled default
`/etc/watchman.json`, `CMakeLists.txt:191-196`), `WATCHMAN_SOCK` — **only**
in the bundled cppclient (`cppclient/WatchmanConnection.cpp:69`), never in
the CLI core — plus `$USER/$LOGNAME/$TMPDIR/$TMP/$HOME` inputs above and
win32 `WATCHMAN_WIN7_COMPAT`.

**`WATCHMAN_STATE_DIR` is NOT read at runtime by the C++ code.** It is only
*written*: the server exports it (with `WATCHMAN_SOCK`) into perf-logger and
mercurial-fsmonitor child environments
(`watchman/PerfSample.cpp:261-278` — value is
`dirname(flags.watchman_state_file)`, `:201-202`;
`watchman/scm/Mercurial.cpp:116-118`) and into trigger children
(`watchman/TriggerCommand.cpp:381-384`, which exports `WATCHMAN_ROOT`,
`WATCHMAN_SOCK`, `WATCHMAN_TRIGGER`).

## 2. Discovery chain — CLIENT side

### 2.1 The C++ CLI as a client

`w_stm_connect` (`watchman/Connect.cpp:15-43`): config `use-unix-domain`
(default true) → `w_stm_connect_unix(get_unix_sock_name(), timeoutms)`
(`watchman/stream_unix.cpp:366-425`):

- too-long path → `E2BIG` (`:373-376`)
- `connect()` failure retried **only** on `ECONNREFUSED`/`ENOENT`, 10 ms
  sleeps, up to `timeoutms/10` attempts (`:397-411`). No client-side unlink
  of stale sockets — clients surface the error.
- `SO_RCVBUF = WATCHMAN_IO_BUF_SIZE` (`:416-422`)

If the first connect fails with `ECONNREFUSED`/`ENOENT`
(`should_start`, `main.cpp:901-903`), the CLI **spawns a server**
(`main.cpp:906-949`): `try_spawn_watchman`
(`main.cpp:823-860`) → config `spawn_watchman_service` site-spawner
(`:847-850`) → macOS launchd → else `run_service_as_daemon`
(`main.cpp:267-306`): flock the pidfile **before** forking (so lock failure
is reportable, `:275-278`), double-fork + setsid, `writePid`, `run_service`.
The spawn loop then retries the command ~10× with backoff doubling from
10 ms (~10 s total) (`main.cpp:919-948`).

Drop-in consequence: if the compat path is not serving watchwoman, any
client that shells out to the C++ `watchman` CLI will *spawn a rival C++
watchman daemon* at the CLI's computed path. The compat link (or replacing
the `watchman` binary) is what prevents that.

### 2.2 `get-sockname` — the discovery protocol

Registered `CMD_DAEMON | CMD_CLIENT | CMD_ALLOW_ANY_USER`
(`watchman/cmds/info.cpp:150-154`), i.e. answerable by the daemon *or* by the
CLI in local client mode (`--no-spawn`).

Response shape (unix):

```json
{
  "version": "<PACKAGE_VERSION>",       // every response, BaseResponse
  "sockname": "<unix path on posix; named pipe on win32>",
  "unix_domain": "<unix path>"          // omitted if UDS disabled
}
```

- `sockname` = `get_sock_name_legacy()` = `flags.unix_sock_name` on posix
  (`watchman/sockname.cpp:17-23`, `cmds/info.cpp:130-134`)
- `unix_domain` = same string, omitted when `disable_unix_socket`
  (`cmds/info.cpp:135-138`)
- `named_pipe` only on win32 (`cmds/info.cpp:140-146`)
- `version` comes from the response envelope
  (`watchman/CommandRegistry.cpp:104`)

Critical nuance: **when a server is reachable, the answer is the server's own
`flags.unix_sock_name`** — i.e. whatever the server computed or was started
with via `--sockname`, *not* the path the client used to reach it. Observed
live on this host: connecting through the compat symlink
`/usr/local/src/watchman-git/watchman/var/run/watchman/rektide-state/sock`
made the legacy daemon answer `"sockname":
"/home/rektide/.local/var/lib/watchman-main/sock"` (its argv value). A
watchwoman started by a socket unit with an explicit `--sockname` must
therefore answer with a path that is itself connectable by the asking client
— which holds as long as the answered path is the socket unit's real path.

### 2.3 Bundled/real clients, in discovery order

Every first-party client: **`$WATCHMAN_SOCK` if set → else exec the watchman
CLI `get-sockname` → connect to the returned path.**

| client | WATCHMAN_SOCK | discovery invocation | fields used | ref |
|---|---|---|---|---|
| pywatchman (bundled) | `:963-965` | `$WATCHMAN_BINARY` or `watchman` (`:602-608`), `--output-encoding=bser get-sockname` (`:967`), BSER-decoded | `unix_domain` → `named_pipe` → `sockname` (sockname asserted present) (`:1001-1011`) | `watchman/python/pywatchman/__init__.py:960-1011` |
| rust `watchman_client` | preset via `Connector::new()` (`rust/watchman_client/src/lib.rs:189-197`) | `watchman --output-encoding bser-v2 get-sockname` (`:226`) | **`sockname` only** (`:251-263`); `GetSockNameResponse{version, sockname, error}` (`rust/watchman_client/src/pdu.rs:33-37`) | same |
| node fb-watchman (bundled `watchman/node/index.js`; npm fb-watchman identical) | `:181-184` | `--no-pretty get-sockname` → **JSON** output (`:189`) | `obj.sockname` (`:270`) | `watchman/node/index.js:116-270` |
| C++ cppclient (eden/sapling) | `:69-72` | `watchman --output-encoding=bser get-sockname` (`:85-88`) | `unix_domain` preferred, `sockname` fallback (`:106-115`; comment cites Ubuntu 20.04 v4.9.0 which only has `sockname`) | `watchman/cppclient/WatchmanConnection.cpp:61-117` |
| humans/scripts | n/a | hardcoded path or `watchman get-sockname` | — | — |

Implications for watchwoman's `get-sockname` implementation:

- must emit `sockname`, ideally also `unix_domain`, plus `version`, in
  **BSER v1, BSER v2, and JSON** depending on the `--output-encoding` /
  `--no-pretty` flags the caller chose (all three call styles exist in the
  wild);
- `sockname` must never be null (pywatchman asserts; rust errors on
  `MissingField`);
- the CLI subprocess must exit 0 — a non-zero exit aborts discovery in every
  client.

Upstream docs corroborate: "invoke `watchman get-sockname` to discover the
location, or if you are invoked via a trigger … `$WATCHMAN_SOCK`"
(`website/docs/socket-interface.md:14-18`).

## 3. The sun_path length "fallback" — it does not exist

The recollection that watchman relocates the socket to a hashed name under
TMPDIR when the path exceeds the unix socket limit is **incorrect** — for
current watchman and for every historical release checked:

- current, client: `strlen(path) >= sizeof(un.sun_path)-1` → log + return
  `E2BIG` (`watchman/stream_unix.cpp:373-376`)
- current, server: same check → listener init fails
  (`watchman/listener.cpp:73-77`)
- `v4.9.0:main.c` `setup_sock_name`: `abort()` on over-length
- `v3.0.0:main.c` and `v2.9.9:main.c`: identical `abort()` — no hash, no
  relocation
- full-text search of the current tree finds no hash-derivation of socket
  names anywhere near sockname computation; the only hashed/derived names in
  the tree are the win32 mutex `Global\Watchman-<pidfile>`
  (`watchman/ProcessLock.cpp:93-102`) and the win32 pipe
  `\\.\pipe\watchman-<user>` (`watchman/main.cpp:645`).

On Linux `sizeof(sun_path) == 108`, so the check rejects paths of ≥107
bytes; the practical budget is 106 chars. Deep home directories therefore do
**not** silently relocate the socket — they produce a hard failure. The
thing that *does* vary with the environment is only the build-flavor choice
in §1.3 (TMPDIR-fallback builds use `$TMPDIR/<user>-state`).

What likely fed the "hash" memory: the ≤3.x-era layouts put the socket in
`$TMPDIR/.watchman.<user>` (v2.9.9/v3.0.0 `compute_file_name`), and other
daemons (tmux, ssh-agent, gpg-agent) do hash/relocate under `/tmp`.

## 4. State-dir contents and semantics

Per-user state dir `<state_dir>/<user>-state/` holds:

| file | mode | writer | refs |
|---|---|---|---|
| `sock` | `srw-------` (sock_access default 0600) | server binds, chmods, unlinks stale | `listener.cpp:66-100` |
| `state` | `0600`, `O_TRUNC` JSON | server load/save | `watchman/state.cpp:86`, `:120-124` |
| `log` | `0600` append; `-` = stdout/stderr | server redirects stdout+stderr there | `main.cpp:146-154` |
| `pid` | `0644`, flock `LOCK_EX\|LOCK_NB` held forever | server (via `ProcessLock`) | `ProcessLock.cpp:33-68`, `:135-162` |

Directory semantics enforced by `compute_file_name` → `create_state_dir` →
`verify_dir_ownership` (`watchman/PathUtils.cpp:154-184`, `:32-152`) — and
these run on **every CLI invocation**, client or server, because computing
the sockname has this side effect (`PathUtils.cpp:217-239`):

- dir is created (0700, `:174-178`) if missing — *symlinked state dirs pass
  the exists() check and are not recreated* (`:158-164`; the comment says
  folly errors on symlinks, hence the explicit check)
- `euid` must own the dir (`:64-75`) — with a symlinked `<user>-state`,
  ownership of the **target** is checked (openDir follows the link)
- any `0022` (group/other write) bit is fatal with a "chmod 0700" hint
  (`:76-87`)
- the dir is `fchmod`-ed to `sock_access`(dir flavor) `| S_ISGID` — default
  `0700|S_ISGID` = `drwx--S---` (`:45-48`, `:128-143`) — note this mutates
  the symlink target, which is fine for user-owned watchwoman dirs
- optional `sock_group` fchown and Linux `secondary_sock_group` ACL
  (`:89-126`)

Pidfile/liveness:

- locking: `flock` chosen deliberately so it transfers through `fork()`
  (`ProcessLock.cpp:51-53`); failure string includes the pid read from the
  file (`:55-66`); written after daemonize via `writePid` (ftruncate+write,
  fd intentionally leaked/never closed) (`:135-162`); acquired pre-fork in
  `run_service_as_daemon` (`main.cpp:271-280`) and in foreground mode
  (`main.cpp:226-232`).
- **no first-party client reads the pidfile.** Liveness is a protocol
  concern: the `get-pid` command returns `{"pid": getpid()}` (CMD_DAEMON
  only) (`watchman/listener.cpp:572-578`), used by the server's own sanity
  thread to detect a rival daemon squatting on the socket
  (`watchman/SanityCheck.cpp:37-76`). Subscribe responses carry the *client's*
  pid via `SO_PEERCRED` (`watchman/stream_unix.cpp:130-146`,
  `watchman/cmds/subscribe.cpp:582`). pywatchman's `self.pid` is its own
  fork-guard, not the server's.

## 5. Drop-in requirements checklist (ranked by real-client hit rate)

1. **`get-sockname` over the wire + CLI subprocess (highest traffic).**
   Every language client execs a `watchman` binary and parses its output
   before ever touching a path. Requirements: exit 0; `version` + `sockname`
   (+ `unix_domain`) keys; BSER v1 (`--output-encoding=bser`), BSER v2
   (`bser-v2`), and JSON (`--no-pretty`) output encodings; answer with a
   connectable path. (`cmds/info.cpp:126-154`; client refs §2.3.)
2. **Compat symlink per installed CLI build family.** The C++ CLI computes
   `<compiled WATCHMAN_STATE_DIR>/<user>-state/sock` and will create/chmod
   that dir if absent, connect if present, or spawn a rival daemon if dead.
   On this host today that means `/usr/local/src/watchman-git/watchman/var/
   run/watchman/rektide-state` (July build) — and `/usr/local/var/run/
   watchman/rektide-state` the moment the August `/usr/local`-prefix build
   is installed. Symlinking the *state dir* (`<user>-state` → watchwoman's
   real dir) survives the ownership/perm enforcement (§4) as long as the
   target is user-owned without 0022 bits. Symlinking just the `sock` file
   also works for connect() but leaves the CLI free to create a real
   `<user>-state` dir — prefer the dir-level link.
3. **`$WATCHMAN_SOCK` honored and exported.** All bundled clients check it
   first; the server sets it for trigger/perf/fsmonitor children
   (`TriggerCommand.cpp:381-384`, `PerfSample.cpp:261-278`,
   `scm/Mercurial.cpp:118`). Watchwoman must keep exporting it in trigger
   environments, or trigger-side scripts using pywatchman/node clients break.
4. **XDG layout** `$XDG_STATE_HOME/watchman/<user>-state/sock` (default
   `$HOME/.local/state`) — only for `WATCHMAN_USE_XDG_STATE_HOME` builds
   (off in both local builds). Watchwoman already binds this natively; it is
   also a sensible canonical home. (`UserDir.cpp:177-193`, `:209-210`.)
5. **TMPDIR fallback** `$TMPDIR|$TMP|/tmp/<user>-state/sock` — only for
   builds compiled with neither macro (autotools `--enable-statedir=no`).
   Rare, but it is the *only* case where TMPDIR depth changes the socket
   location. (`UserDir.cpp:77-87`, `:213-214`.)
6. **Ancient flat layout** `$TMPDIR/.watchman.<user>` (≤ v3.x clients that
   hardcode) — probably ignorable in 2026; listed for completeness.
   (v3.0.0 `compute_file_name`.)

Supporting requirements applying at every rank:

- **Path length budget**: keep the served socket path ≤ 106 bytes on Linux;
   there is no fallback — clients get `E2BIG` (`stream_unix.cpp:373-376`) and
   servers fail to bind (`listener.cpp:73-77`).
- **Stale socket**: server must `unlink` before `bind` (`listener.cpp:87`);
   clients never unlink — they retry on `ECONNREFUSED`/`ENOENT` at 10 ms
   granularity for the caller-supplied timeout (`stream_unix.cpp:397-411`),
   and the CLI retries ~10 s with doubling backoff after spawning
   (`main.cpp:919-948`). A socket-activated watchwoman satisfies all of this
   by existing at the path.
- **Modes**: socket file 0600, state dir 0700+S_ISGID user-owned; a
  replacement should match so the C++ CLI's `verify_dir_ownership` never
  fatals against watchwoman's dirs (`PathUtils.cpp:32-152`).
- **`--inetd`**: listener on stdin fd (`main.cpp:134-137`,
  `listener.cpp:50-62`); no abstract sockets; no LISTEN_FDS support
  upstream.
- **No runtime `WATCHMAN_STATE_DIR` env override exists** to replicate —
  but `WATCHMAN_TEST_STATE_DIR` (verbatim state dir) and `WATCHMAN_NO_SPAWN`
  are read and should be honored for test parity (`UserDir.cpp:200-203`,
  `main.cpp:754`).
- **Config file** `/etc/watchman.json` (or `$WATCHMAN_CONFIG_FILE`, with a
  `.default` fallback) supplies `use-unix-domain`, `sock_access`,
  `sock_group`, `secondary_sock_group`, `log_dir`,
  `spawn_watchman_service` (`WatchmanConfig.cpp:25-68`; users of these keys
  cited above).
- **`get-pid`** must exist and return the daemon pid (`listener.cpp:572-578`)
  — it is the liveness primitive (sanity thread, ops scripts).

## 6. Live-state observations on this host (2026-08-30)

- Two listeners: `~/.local/state/watchman/rektide-state/sock` (watchwoman,
  socket-activated, `--sockname`-overridden, `--foreground-daemon`) and
  `~/.local/var/lib/watchman-main/sock` (legacy C++ daemon run by hand since
  Aug 25 with explicit `--statefile/--pidfile/--sockname/--logfile`).
- Compat link in place only for the July build's state dir:
  `/usr/local/src/watchman-git/watchman/var/run/watchman/rektide-state →
  ~/.local/var/lib/watchman-main` — i.e. it currently feeds the **legacy
  daemon**, not watchwoman.
- `/usr/local/var/run/watchman` does not exist; the August rebuild (whose
  compiled default lives there) is built but its bin/ is not installed into
  `/usr/local/bin` yet.
- `watchman get-sockname` through that link returns the legacy daemon's argv
  sockname (`watchman-main/sock`), demonstrating §2.2's "server answers with
  its own flag" behavior — a client honoring that answer bypasses the compat
  link entirely, which is fine while both paths lead to a live daemon but is
  the thing to get right when watchwoman takes over the link.

## Cross-references

- [`files/watchwoman/status-watchwoman.sh`](/files/watchwoman/status-watchwoman.sh) — current deploy's health/drift checks; its "classic-watchman compat symlink" tripwire is the mechanism ranked #2 above, and its XDG zeroconf assumption matches §1.3 case 4 (note: both local C++ builds are XDG-OFF, so the XDG path is *not* what the installed CLI computes — it is only watchwoman's chosen canonical path).
- [`watchman.src.pb`](/watchman.src.pb) / [`watchwoman.src.pb`](/watchwoman.src.pb) — build manifests for the getdeps checkout and the replacement daemon.
- Upstream docs: [Socket Interface](https://facebook.github.io/watchman/docs/socket-interface.html) (corroborates `get-sockname` + `$WATCHMAN_SOCK` as the discovery contract).

# Addendum: 2026-09-08 — the jj-background-monitor feedback loop

## Incident

A watchman trigger named `jj-background-monitor` (command `jj --quiet util
snapshot`) on this repo entered a self-sustaining feedback loop during a
`jj commit` session: **12,000+ concurrent `jj util snapshot` processes**
(~20 spawns/sec), all but one parked in `locks_lock_inode_wait`, queueing on
the jj repo lock. The spawner was the watchwoman daemon (`--sockname
~/.local/state/watchman/rektide-state/sock --foreground-daemon`, pid 806505
at the time) executing the trigger. Two `jj commit` attempts starved behind
the herd and timed out.

## Mechanism

The trigger expression *intended* to exclude jj/colocated-git state:

```json
"expression": ["not", ["anyof",
  ["name", [".git", ".jj"], "wholename"],
  ["dirname", ".git"],
  ["dirname", ".jj"]
]],
"append_files": false
```

**watchman's `dirname` term matches exactly one path component** — it excludes
files *directly* under `.jj`/`.git`, not deeper paths. A colocated jj snapshot
writes deep under both trees (`.jj/repo/op_heads/*`, `.git/refs/*`, …); each
such write re-fired the trigger, and each spawned snapshot wrote more state:
a genuine feedback loop. The `["name", …, "wholename"]` term only covers the
directory entries themselves.

## Intervention and current state

1. SIGSTOP of the daemon + SIGKILL of the worker herd (twice — the loop
   re-seeded from buffered events after the first CONT).
2. `watchwoman trigger-list` captured the definition, then
   `watchwoman trigger-del /home/rektide/src/compfuzor jj-background-monitor`.
   The watch and all other roots are untouched; a sweep of every watched
   root (≈50) found **zero other triggers** — this was the only armed one.
3. The definition is preserved at
   [`.test-agent/watchwoman/jj-background-monitor.trigger.json`](/.test-agent/watchwoman/jj-background-monitor.trigger.json)
   (gitignored scratch).

The trigger name appears in no source repo and not in the watchwoman binary:
it was registered by hand or by a long-gone script.

**Decision (operator, 2026-09-08): leave the trigger off.** ("i used to have
more triggers they sometimes hurt.")

## Durable fixes, ranked

1. **Fork default (recommended)**: watchwoman already honors per-root
   `.watchmanconfig` `ignore_dirs`
   (`crates/watchwoman/src/daemon/state.rs:139` → `load_watchmanconfig_ignores`,
   applied in `watcher::initial_scan` and the root's ignore set). Make
   `.git`/`.jj`/`.hg` *default-ignored* unless a root overrides — then any
   jj/git trigger pattern becomes structurally loop-safe on every repo.
2. **Per-repo config (available today)**: drop
   `{"ignore_dirs": [".jj", ".git"]}` as `.watchmanconfig` in a repo root,
   then `watch-del` + re-watch so it takes effect.
3. **Correct expression (belt-and-suspenders)** if a trigger is ever wanted
   again, replace the one-level `dirname` terms with subtree matches, e.g.
   `["not", ["anyof", ["name", [".git",".jj"], "wholename"],
   ["match", ".git/**", "wholename"], ["match", ".jj/**", "wholename"]]]`.

A trigger that shells out to a VCS *inside the watched root* is only ever one
shallow-exclusion bug away from this loop — which is why the ignore_dirs
default (fix 1) is the one that generalizes.
