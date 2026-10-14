# Read-only snapshot: no API calls, service discovery, or credential loading.
exec python3 - {{ OPENCODE_BUS_PROXY_PORT | int }} "$@" <<'PY'
import argparse
import os
from pathlib import Path
import subprocess


def tmux_panes():
    try:
        result = subprocess.run(
            ["tmux", "list-panes", "-a", "-F",
             "#{pane_pid}\t#{pane_id}\t#{session_name}:#{window_index}.#{pane_index}\t#{window_name}"],
            capture_output=True, text=True, timeout=3,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []
    return [line.split("\t", 3) for line in result.stdout.splitlines()
            if len(line.split("\t", 3)) == 4] if result.returncode == 0 else []


def tmux_location(proc, panes):
    # Ancestry is stronger than inherited environment (which may be stale).
    current = proc
    seen = set()
    while current.name not in seen:
        seen.add(current.name)
        matches = [f"{location} ({pane}, {window})" for pid, pane, location, window
                   in panes if pid == current.name]
        if matches:
            return "; ".join(matches)
        try:
            status = (current / "status").read_text()
            parent = next(line.split()[1] for line in status.splitlines()
                          if line.startswith("PPid:"))
        except (OSError, StopIteration):
            break
        if parent == "0":
            break
        current = proc.parent / parent
    try:
        environment = (proc / "environ").read_bytes().split(b"\0")
        pane_id = next(value.split(b"=", 1)[1].decode() for value in environment
                       if value.startswith(b"TMUX_PANE="))
    except (OSError, StopIteration):
        return "not found"
    matches = [f"{location} ({pane}, {window}; inherited)"
               for _, pane, location, window in panes if pane == pane_id]
    return "; ".join(matches) if matches else f"{pane_id} (tmux server unavailable)"


def proxy_inodes(proc, port):
    inodes = set()
    for name in ("tcp", "tcp6"):
        try:
            lines = (proc / "net" / name).read_text().splitlines()[1:]
        except FileNotFoundError:
            if name == "tcp6" and proc.exists():
                continue  # IPv6 may be disabled.
            raise
        for line in lines:
            fields = line.split()
            address, remote_port = fields[2].split(":")
            # Match the authored IPv4 loopback listener, including mapped IPv6.
            if (fields[3] == "01" and int(remote_port, 16) == port
                    and address in ("0100007F", "0000000000000000FFFF00000100007F")):
                inodes.add(fields[9])
    return inodes


def inspect(proc, port):
    wanted = proxy_inodes(proc, port)
    for fd in (proc / "fd").iterdir():
        try:
            target = fd.readlink().as_posix()
        except FileNotFoundError:
            continue  # Socket closed during snapshot.
        if target.startswith("socket:[") and target[8:-1] in wanted:
            return True
    return False


def report(root, uid, port, panes):
    total = using = unknown = 0
    rows = []
    for proc in sorted((p for p in root.iterdir() if p.name.isdigit()),
                       key=lambda p: int(p.name)):
        try:
            if proc.stat().st_uid != uid or (proc / "comm").read_text().strip() != "opencode":
                continue
            args = (proc / "cmdline").read_bytes().split(b"\0")
            if len(args) > 1 and args[1] == b"serve":
                continue
            if not args[0]:  # Zombie, not a running instance.
                continue
        except FileNotFoundError:
            continue
        total += 1
        try:
            connected = inspect(proc, port)
        except FileNotFoundError:
            if not proc.exists():
                total -= 1
                continue
            connected = None
        except PermissionError:
            connected = None
        if connected:
            using += 1
            continue
        if connected is None:
            unknown += 1
        try:
            cwd = str((proc / "cwd").readlink())
        except OSError:
            cwd = "unavailable"
        rows.append((proc.name, "unknown" if connected is None else "not using",
                     tmux_location(proc, panes), cwd))
    print(f"OpenCode clients without observed proxy use (127.0.0.1:{port}):")
    print("PID\tSTATUS\tTMUX\tCWD")
    for row in rows:
        print("\t".join(value.replace("\n", "\\n").replace("\t", "\\t") for value in row))
    if not rows:
        print("(none)")
    ratio = f"{using / total:.3f}" if total else "n/a"
    print(f"usage/total: {using}/{total} = {ratio}; unknown: {unknown}")
    return 2 if unknown else (1 if using < total else 0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Report current user's OpenCode proxy usage and tmux locations.")
    parser.add_argument("port", type=int)
    args = parser.parse_args()
    raise SystemExit(report(Path("/proc"), os.getuid(), args.port, tmux_panes()))
PY
