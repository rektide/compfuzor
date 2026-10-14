#!/usr/bin/env python3
"""Exercise the generated reporter against deterministic procfs snapshots."""
import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "files/opencode-bus-proxy/status-usage.sh"
MODULE = {"__name__": "usage_test"}
exec(compile(SOURCE.read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0],
             str(SOURCE), "exec"), MODULE)


class UsageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir="/tmp/opencode", prefix="proxy-usage-")
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)

    def process(self, pid, *, name="opencode", args=b"opencode\0", parent=1,
                remote="0100007F:C0DC", state="01", tcp6=False, inode="42"):
        proc = self.proc / str(pid)
        (proc / "net").mkdir(parents=True)
        (proc / "fd").mkdir()
        (proc / "comm").write_text(name + "\n")
        (proc / "cmdline").write_bytes(args)
        (proc / "status").write_text(f"PPid:\t{parent}\n")
        (proc / "environ").write_bytes(b"")
        (proc / "cwd").symlink_to("/work/project")
        line = f"0: 0100007F:ABCD {remote} {state} 0:0 0:0 0 1000 0 {inode}\n"
        for name in ("tcp", "tcp6"):
            (proc / "net" / name).write_text("header\n" + (line if (name == "tcp6") == tcp6 else ""))
        (proc / "fd/10").symlink_to(f"socket:[{inode}]")
        return proc

    def report(self, panes=(), uid=None):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = MODULE["report"](self.proc, os.getuid() if uid is None else uid, 49372, panes)
        return code, output.getvalue()

    def add_socket(self, proc, inode, remote):
        with (proc / "net/tcp").open("a") as table:
            table.write(f"0: 0100007F:ABCD {remote} 01 0:0 0:0 0 1000 0 {inode}\n")
        (proc / f"fd/{inode}").symlink_to(f"socket:[{inode}]")

    def test_counts_clients_once_and_excludes_servers_and_other_processes(self):
        client = self.process(10)
        (client / "fd/11").symlink_to("socket:[42]")
        self.process(20, remote="0100007F:C0DD")  # Direct origin.
        self.process(30, args=b"opencode\0serve\0--port\049373\0")
        self.process(40, name="opencode-bus-pr")
        code, text = self.report()
        self.assertEqual(code, 1)
        self.assertIn("usage/total: 1/2 = 0.500", text)
        self.assertIn("20\tnot using", text)
        self.assertNotIn("10\tnot using", text)
        self.assertEqual(self.report(uid=os.getuid() + 1)[0], 0)
        self.assertIn("49372\t1\texpected proxy", text)
        self.assertIn("49373\t1", text)
        self.assertLess(text.index("expected proxy"), text.index("49373\t1"))

    def test_port_histogram_sorted_with_expected_pinned_first(self):
        client = self.process(10, remote="0100007F:01BB", inode="50")  # 443
        self.add_socket(client, "51", "0100007F:1538")  # 5432
        self.add_socket(client, "52", "0100007F:1538")  # Same port twice: one client.
        self.add_socket(client, "53", "0100007F:EA60")  # 60000
        code, text = self.report()
        self.assertEqual(code, 1)
        self.assertIn("49372\t0\texpected proxy", text)
        self.assertIn("443\t1", text)
        self.assertIn("5432\t1", text)
        self.assertIn("60000\t1", text)
        positions = [text.index(f"{line}\t") for line in ("49372", "443", "5432", "60000")]
        self.assertEqual(positions, sorted(positions))

    def test_requires_established_loopback_destination(self):
        self.process(10, remote="0200007F:1538")  # 127.0.0.2:5432 isn't our listener.
        self.process(20, state="0A")  # Listener isn't client usage.
        self.process(30, state="08")  # CLOSE_WAIT isn't active usage.
        code, text = self.report()
        self.assertEqual(code, 1)
        self.assertIn("usage/total: 0/3", text)
        self.assertIn("49372\t0\texpected proxy", text)
        self.assertIn("5432\t1", text)  # Other loopback addresses still count per port.
        self.assertNotIn("49373\t", text)

    def test_mapped_ipv6_and_empty_report(self):
        self.assertIn("0/0 = n/a", self.report()[1])
        self.assertIn("49372\t0\texpected proxy", self.report()[1])
        self.process(10, remote="0000000000000000FFFF00000100007F:C0DC", tcp6=True)
        code, text = self.report()
        self.assertEqual(code, 0)
        self.assertIn("1/1 = 1.000", text)
        self.assertIn("49372\t1\texpected proxy", text)

    def test_missing_socket_data_is_unknown(self):
        proc = self.process(10)
        (proc / "net/tcp").unlink()
        code, text = self.report()
        self.assertEqual(code, 2)
        self.assertIn("10\tunknown", text)
        self.assertIn("unknown: 1", text)
        self.assertIn("49372\t0\texpected proxy", text)

    def test_tmux_ancestry_then_inherited_fallback(self):
        client = self.process(10, parent=20, remote="0100007F:C0DD")
        self.process(20, name="zsh", parent=30)
        self.process(30, name="zsh")
        (client / "environ").write_bytes(b"TMUX_PANE=%9\0SECRET=not-shown\0")
        panes = [("30", "%2", "work:4.1", "coding"), ("90", "%9", "old:1.0", "old")]
        text = self.report(panes)[1]
        self.assertIn("work:4.1 (%2, coding)", text)
        self.assertIn("/work/project", text)
        self.assertNotIn("SECRET", text)
        self.assertNotIn("inherited", text)
        self.assertIn("old:1.0 (%9, old; inherited)", self.report(panes[1:])[1])
        self.assertIn("%9 (tmux server unavailable)", self.report()[1])


if __name__ == "__main__":
    unittest.main()
