# Live resident-memory view of this account's OpenCode client instances.
# Read-only /proc snapshot: no server contact, no lifecycle action.
# _bin supplies the shebang.
exec python3 - "$@" <<'PY'
import argparse
import os
from pathlib import Path
import subprocess


def tmux_panes():
    """(pane_pid, pane_id, session, window_index, window_name) per pane."""
    try:
        result = subprocess.run(
            ["tmux", "list-panes", "-a", "-F",
             "#{pane_pid}\t#{pane_id}\t#{session_name}\t#{window_index}\t#{window_name}"],
            capture_output=True, text=True, timeout=3,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []
    if result.returncode != 0:
        return []
    return [line.split("\t", 4) for line in result.stdout.splitlines()
            if len(line.split("\t", 4)) == 5]


def window_display(index, name):
    # "3.build" addresses the pane and reads well; spaces break columns.
    return index if not name else index + "." + name.replace(" ", "_")


def tmux_location(proc, panes):
    """(session, window_display, inherited); None when unresolvable.

    Ancestry beats the inherited environment, which can be stale; the
    TMUX_PANE fallback marks its result so readers can distrust it.
    """
    current = proc
    seen = set()
    while current.name not in seen:
        seen.add(current.name)
        for pane_pid, _, session, window, name in panes:
            if pane_pid == current.name:
                return session, window_display(window, name), False
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
        return None, None, False
    for _, pane, session, window, name in panes:
        if pane == pane_id:
            return session, window_display(window, name), True
    return None, None, False


def memory_kb(proc):
    """(rss_kb, pss_kb); pss_kb None when smaps_rollup is unreadable."""
    status = (proc / "status").read_text()
    rss = int(next(line.split()[1] for line in status.splitlines()
                   if line.startswith("VmRSS:")))
    try:
        rollup = (proc / "smaps_rollup").read_text()
        pss = int(next(line.split()[1] for line in rollup.splitlines()
                       if line.startswith("Pss:")))
    except (OSError, StopIteration):
        pss = None
    return rss, pss


def directory(proc, home):
    try:
        cwd = str((proc / "cwd").readlink())
    except OSError:
        return "unavailable"
    return "~" + cwd[len(str(home)):] if cwd.startswith(str(home) + "/") else cwd


def report(root, uid, panes, count, home):
    clients = []
    server = None
    for proc in sorted((p for p in root.iterdir() if p.name.isdigit()),
                       key=lambda p: int(p.name)):
        try:
            if proc.stat().st_uid != uid or (proc / "comm").read_text().strip() != "opencode":
                continue
            args = (proc / "cmdline").read_bytes().split(b"\0")
            if not args[0]:  # Zombie, not a running instance.
                continue
            rss, pss = memory_kb(proc)
        except (FileNotFoundError, StopIteration):
            continue  # Process vanished mid-snapshot.
        if len(args) > 1 and args[1] == b"serve":
            server = (proc.name, rss)
            continue
        session, window, inherited = tmux_location(proc, panes)
        clients.append((rss, int(proc.name), proc, session, window, inherited, pss))
    clients.sort(key=lambda row: (-row[0], row[1]))
    shown = clients[:count] if count else clients

    def cell_mb(kb):
        return "-" if kb is None else f"{kb / 1024:.1f}"

    rows = []
    for rss, pid, proc, session, window, inherited, pss in shown:
        label = "-" if session is None else session + ("*" if inherited else "")
        rows.append([str(pid), cell_mb(rss), cell_mb(pss),
                     label, window or "-", directory(proc, home)])
    headers = ["PID", "RSS_MB", "PSS_MB", "SESSION", "WIN", "DIR"]
    widths = [max([len(header)] + [len(row[i]) for row in rows])
              for i, header in enumerate(headers)]

    def line(cells):
        prefix = [cells[i].rjust(widths[i]) for i in range(3)]
        suffix = [cells[i].ljust(widths[i]) for i in (3, 4)] + [cells[5]]
        return "  ".join(prefix + suffix).rstrip()

    print(line(headers))
    for row in rows:
        print(line(row))
    total = sum(row[0] for row in clients) / 1024
    footnote = ""
    if server:
        footnote = (f"; origin serve pid {server[0]}: {server[1] / 1024:.1f} MB"
                    " resident (not ranked)")
    scope = f"{len(rows)} of {len(clients)}" if count else str(len(clients))
    print(f"\n{scope} client instances; combined RSS {total:.1f} MB{footnote}")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="List the largest resident OpenCode client instances with tmux locations.")
    parser.add_argument("-n", "--count", type=int, default=8,
                        help="how many instances to show (0: all)")
    args = parser.parse_args()
    raise SystemExit(report(Path("/proc"), os.getuid(), tmux_panes(),
                            args.count, Path.home()))
PY
