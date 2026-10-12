#!/usr/bin/env python3
"""Render factory bins with Ansible; exercise only mock NSS/accounts and sudoers."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
state_path = pathlib.Path(os.environ["MOCK_STATE"])
state = json.loads(state_path.read_text())
cmd, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps([cmd, *args]) + "\n")
if cmd == "getent":
    table, key = args
    for name, fields in state[table].items():
        if name == key or str(fields[0]) == key:
            if table == "passwd":
                print(f"{name}:x:{fields[0]}:{fields[1]}::/home/{name}:/bin/bash")
            else:
                print(f"{name}:x:{fields[0]}:")
            sys.exit(0)
    sys.exit(2)
elif cmd == "groupadd":
    state["group"][args[-1]] = [int(args[1])]
elif cmd == "useradd":
    state["passwd"][args[-1]] = [int(args[args.index("-u") + 1]),
                               state["group"][args[args.index("-g") + 1]][0]]
elif cmd == "userdel":
    del state["passwd"][args[-1]]
elif cmd == "groupdel":
    del state["group"][args[-1]]
elif cmd == "id":
    print("mock test user")
elif cmd == "visudo":
    pending = pathlib.Path(args[-1])
    assert pending.name.startswith(".61-user-test-")
    assert pending.stat().st_mode & 0o777 == 0o440
    assert pending.read_text() == "operator ALL=(zimtest) NOPASSWD: ALL\n"
    sys.exit(int(os.environ.get("MOCK_VISUDO_FAIL", "0")))
else:
    raise AssertionError(cmd)
state_path.write_text(json.dumps(state))
'''


class FactoryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.render_tmp = tempfile.TemporaryDirectory(dir="/tmp/opencode", prefix="user-test-render-")
        root = Path(cls.render_tmp.name)
        (root / "files").symlink_to(ROOT / "files", target_is_directory=True)
        variables = yaml.safe_load((ROOT / "user-test.etc.pb").read_text())[0]["vars"]
        variables.update(TYPE="user-test", DIR=str(root), BINS_DIR=str(root / "bin"),
                         BINMODE="0755", DEFAULT_HELPERS=[])
        play = [{"hosts": "all", "gather_facts": False, "vars": variables,
                 "tasks": [{"ansible.builtin.import_tasks": str(ROOT / "tasks/compfuzor/bins.tasks")}]}]
        playbook = root / "render.pb"
        playbook.write_text(yaml.safe_dump(play, sort_keys=False))
        result = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
            cwd=ROOT, env={**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")},
            capture_output=True, text=True,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        cls.scripts = {path.name: path.read_text() for path in (root / "bin").glob("*.sh")}
        for path in (root / "bin").glob("*.sh"):
            subprocess.run(["bash", "-n", str(path)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.render_tmp.cleanup()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir="/tmp/opencode", prefix="user-test-mock-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sudoers = self.root / "sudoers.d"
        self.sudoers.mkdir()
        self.grant = self.sudoers / "61-user-test-zimtest"
        self.state_path = self.root / "state.json"
        self.log = self.root / "calls.jsonl"
        self.log.touch()
        self.set_state({}, {})
        mock = self.root / "mock.py"
        mock.write_text(MOCK)
        mock.chmod(0o755)
        for command in ("getent", "groupadd", "useradd", "userdel", "groupdel", "id", "visudo"):
            (self.root / command).symlink_to(mock)
        for name, content in self.scripts.items():
            # Redirect the fixed privileged destination only in test copies.
            (self.root / name).write_text(content.replace("/etc/sudoers.d", str(self.sudoers)))

    def set_state(self, users, groups):
        self.state_path.write_text(json.dumps({"passwd": users, "group": groups}))

    def run_bin(self, action, *names, **env):
        return subprocess.run(
            ["bash", str(self.root / f"user-{action}.sh"), *names],
            env={**os.environ, "PATH": f"{self.root}:{os.environ['PATH']}",
                 "MOCK_STATE": str(self.state_path), "MOCK_LOG": str(self.log),
                 "USER_TEST_BASE_UID": "61000", "USER_TEST_UID_SPAN": "3",
                 "USER_TEST_OPERATOR": "operator", "USER_TEST_USERS": "", **env},
            capture_output=True, text=True, timeout=10,
        )

    def mutations(self):
        return [call for line in self.log.read_text().splitlines()
                if (call := json.loads(line))[0] in ("useradd", "groupadd", "userdel", "groupdel", "visudo")]

    def test_wrap_exhaustion_and_idempotence(self):
        checksum = int(subprocess.check_output(["cksum"], input=b"zimtest").split()[0])
        start = checksum % 3
        free = 61000 + (start + 2) % 3
        # Occupy the other slots in each namespace; the only free slot requires wrapping.
        self.set_state({"occupied": [61000 + start, 1000]},
                       {"occupied": [61000 + (start + 1) % 3]})
        result = self.run_bin("add", "zimtest")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        state = json.loads(self.state_path.read_text())
        self.assertEqual(state["passwd"]["zimtest"], [free, free])
        self.assertEqual(self.grant.read_text(), "operator ALL=(zimtest) NOPASSWD: ALL\n")
        self.log.write_text("")
        self.assertEqual(self.run_bin("add", "zimtest").returncode, 0)
        self.assertEqual(self.mutations(), [])
        self.log.write_text("")
        result = self.run_bin("add", "another")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exhausted", result.stderr)
        self.assertEqual(self.mutations(), [])
        numeric_queries = [call[2] for line in self.log.read_text().splitlines()
                           if (call := json.loads(line))[0] == "getent" and call[2].isdigit()]
        self.assertTrue(all(61000 <= int(uid) < 61003 for uid in numeric_queries))

    def test_ordinary_or_mismatched_account_rejected(self):
        for uid, gid, group_gid in ((1000, 1000, 1000), (61000, 1000, 1000), (61000, 61000, 61001)):
            for action in ("add", "remove"):
                with self.subTest(action=action, uid=uid, gid=gid):
                    self.set_state({"zimtest": [uid, gid]}, {"zimtest": [group_gid]})
                    self.grant.write_text("existing grant\n")
                    self.assertNotEqual(self.run_bin(action, "zimtest").returncode, 0)
                    self.assertEqual(self.mutations(), [])
                    self.assertEqual(self.grant.read_text(), "existing grant\n")

    def test_unsafe_names_and_bands_rejected(self):
        for action in ("add", "remove", "status"):
            for name in ("../root", "bad.name", "-option", "a ALL=(root)", "a" * 33):
                self.assertNotEqual(self.run_bin(action, name).returncode, 0)
        self.assertNotEqual(self.run_bin("add", "zimtest", USER_TEST_OPERATOR="root ALL=(ALL)").returncode, 0)
        for action in ("add", "remove"):
            for base, span in (("0", "3"), ("61000", "0"), ("61000", "-1"), ("x", "3"), ("4294967294", "3")):
                self.assertNotEqual(self.run_bin(action, "zimtest", USER_TEST_BASE_UID=base,
                                                USER_TEST_UID_SPAN=span).returncode, 0)
        self.assertEqual(self.mutations(), [])

    def test_unrelated_group_preserved(self):
        for gid in (1000, 61000):
            self.set_state({}, {"zimtest": [gid]})
            self.assertNotEqual(self.run_bin("add", "zimtest").returncode, 0)
            self.assertEqual(self.run_bin("remove", "zimtest").returncode, 0)
            self.assertEqual(json.loads(self.state_path.read_text())["group"], {"zimtest": [gid]})
            self.assertEqual(self.mutations(), [])

    def test_sudoers_failure_preserves_previous_grant(self):
        self.set_state({"zimtest": [61000, 61000]}, {"zimtest": [61000]})
        for existing in (False, True):
            with self.subTest(existing=existing):
                if existing:
                    self.grant.write_text("previous operator grant\n")
                result = self.run_bin("add", "zimtest", MOCK_VISUDO_FAIL="1")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(self.sudoers.iterdir()), [self.grant] if existing else [])
                if existing:
                    self.assertEqual(self.grant.read_text(), "previous operator grant\n")

    def test_remove_and_repeat(self):
        self.set_state({"zimtest": [61000, 61000]}, {"zimtest": [61000]})
        self.grant.write_text("grant\n")
        result = self.run_bin("remove", "zimtest")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(self.state_path.read_text()), {"passwd": {}, "group": {}})
        self.assertFalse(self.grant.exists())
        self.log.write_text("")
        self.assertEqual(self.run_bin("remove", "zimtest").returncode, 0)
        self.assertEqual(self.mutations(), [])


if __name__ == "__main__":
    unittest.main()
