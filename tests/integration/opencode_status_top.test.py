#!/usr/bin/env python3
"""Exercise the resident-memory top listing against deterministic procfs snapshots."""
import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "files/opencode/status-top.sh"
MODULE = {"__name__": "status_top_test"}
exec(compile(SOURCE.read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0],
             str(SOURCE), "exec"), MODULE)


class StatusTopTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir="/tmp/opencode", prefix="status-top-")
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)
        self.home = Path("/home/tester")

    def process(self, pid, *, name="opencode", args=b"opencode\0", parent=1,
                rss=100, pss=50, environ=b"", cwd="/home/tester/src/tool"):
        proc = self.proc / str(pid)
        proc.mkdir(parents=True)
        (proc / "comm").write_text(name + "\n")
        (proc / "cmdline").write_bytes(args)
        (proc / "status").write_text(f"Name:\t{name}\nPPid:\t{parent}\nVmRSS:\t{rss} kB\n")
        if pss is not None:
            (proc / "smaps_rollup").write_text(f"Rss:\t{rss} kB\nPss:\t{pss} kB\n")
        (proc / "environ").write_bytes(environ)
        (proc / "cwd").symlink_to(cwd)
        return proc

    def report(self, panes=(), count=8, uid=None):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = MODULE["report"](self.proc, os.getuid() if uid is None else uid,
                                    panes, count, self.home)
        return code, output.getvalue()

    def test_ranks_by_rss_and_limits_to_count(self):
        for pid, rss_mb in ((10, 400), (11, 900), (12, 100), (13, 700), (14, 600),
                            (15, 500), (16, 800), (17, 300), (18, 200), (19, 100)):
            self.process(pid, rss=rss_mb * 1024, pss=rss_mb * 512,
                         cwd=f"/home/tester/src/p{pid}")
        code, text = self.report(count=8)
        self.assertEqual(code, 0)
        lines = text.splitlines()
        self.assertEqual(lines[0].split(), ["PID", "RSS_MB", "PSS_MB", "SESSION", "WIN", "DIR"])
        pids = [line.split()[0] for line in lines[1:9]]
        self.assertEqual(pids, ["11", "16", "13", "14", "15", "10", "17", "18"])
        self.assertNotIn("19", text)
        self.assertIn("8 of 10 client instances", text)
        self.assertIn("combined RSS 4600.0 MB", text)
        self.assertIn("~/src/p11", text)

    def test_zero_count_lists_everything_and_unknown_pss_is_blank(self):
        self.process(10, rss=300, pss=None)
        code, text = self.report(count=0)
        self.assertEqual(code, 0)
        self.assertIn("1 client instance", text)
        row = text.splitlines()[1].split()
        self.assertEqual(row[2], "-")  # No smaps_rollup: PSS stays blank.

    def test_excludes_server_zombies_and_other_processes(self):
        self.process(10, args=b"opencode\0serve\0--port\049373\0",
                     rss=5_120_000, pss=4_096_000)
        self.process(11, args=b"\0", rss=9_999)  # Zombie.
        self.process(12, name="opencode-bus-pr", rss=9_999)
        self.process(13, rss=122_880, pss=61_440)
        code, text = self.report()
        self.assertEqual(code, 0)
        self.assertNotIn("5000.0", text.splitlines()[0])
        self.assertIn("origin serve pid 10: 5000.0 MB resident (not ranked)", text)
        self.assertNotIn("9999", text)
        self.assertFalse(any(line.split()[:1] == ["11"] for line in text.splitlines()))
        self.assertTrue(any(line.split()[:1] == ["13"] for line in text.splitlines()))

    def test_tmux_ancestry_then_inherited_fallback(self):
        client = self.process(10, parent=20, rss=100, pss=40)
        self.process(20, name="zsh", parent=30, rss=1,
                     cwd="/home/tester")  # Pane shell found by ancestry.
        self.process(30, name="zsh", rss=1, cwd="/home/tester")
        self.process(40, parent=50, rss=100, pss=40,
                     environ=b"TMUX_PANE=%9\0")  # No ancestry: inherited env.
        self.process(50, name="zsh", rss=1, cwd="/home/tester")
        panes = [("30", "%2", "work", "4", "big feature"),
                 ("90", "%9", "old", "2", "stale")]
        text = self.report(panes=panes)[1]
        rows = {line.split()[0]: line.split() for line in text.splitlines()[1:3]}
        self.assertEqual(rows["10"][3], "work")
        self.assertEqual(rows["10"][4], "4.big_feature")
        self.assertEqual(rows["40"][3], "old*")  # Inherited location is marked.
        self.assertEqual(rows["40"][4], "2.stale")

    def test_home_and_foreign_directories(self):
        self.process(10, rss=100, pss=50, cwd="/home/tester/src/x")
        self.process(11, rss=100, pss=50, cwd="/opt/other")
        text = self.report()[1]
        self.assertIn("~/src/x", text)
        self.assertIn("/opt/other", text)

    def test_no_clients(self):
        code, text = self.report()
        self.assertEqual(code, 0)
        self.assertIn("0 client instances", text)
        self.assertIn("combined RSS 0.0 MB", text)


if __name__ == "__main__":
    unittest.main()
