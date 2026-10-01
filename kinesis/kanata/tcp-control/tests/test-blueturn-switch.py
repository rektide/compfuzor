#!/usr/bin/python3
"""Stdlib unittest suite for scripts/blueturn-switch.

Runs the helper as a subprocess (the deployed invocation shape) against
a loopback stub server, overriding only the documented environment
knobs. Nothing here touches port 16666 or the live services.

    python3 tests/test-blueturn-switch.py        # via unittest.main
"""

import os
import socket
import subprocess
import sys
import threading
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / "scripts" / "blueturn-switch"


class StubPedal:
    """One-acceptance TCP stub capturing the first received line."""

    def __init__(self):
        self.sock = socket.create_server(("127.0.0.1", 0), backlog=1)
        self.addr = f"127.0.0.1:{self.sock.getsockname()[1]}"
        self.received = None
        self.connections = 0

    def serve_once(self):
        self.sock.settimeout(5)
        conn, _ = self.sock.accept()
        self.connections += 1
        conn.settimeout(5)
        with conn.makefile("rb") as reader:
            self.received = reader.readline(4096)
        conn.close()

    def close(self):
        self.sock.close()


class HelperTestCase(unittest.TestCase):
    def run_helper(self, *argv, addr_env=None, timeout_env=None):
        env = dict(os.environ)
        env.pop("BLUETURN_SWITCH_TIMEOUT", None)
        if addr_env is not None:
            env["BLUETURN_SWITCH_ADDR"] = addr_env
        if timeout_env is not None:
            env["BLUETURN_SWITCH_TIMEOUT"] = timeout_env
        return subprocess.run(
            [sys.executable, str(HELPER), *argv],
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )

    def test_sends_pages_changelayer_line(self):
        stub = StubPedal()
        try:
            server = threading.Thread(target=stub.serve_once, daemon=True)
            server.start()
            proc = self.run_helper("pages", addr_env=stub.addr)
            server.join(5)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(stub.connections, 1)
            self.assertEqual(stub.received, b'{"ChangeLayer":{"new":"pages"}}\n')
        finally:
            stub.close()

    def test_sends_media_changelayer_line(self):
        stub = StubPedal()
        try:
            server = threading.Thread(target=stub.serve_once, daemon=True)
            server.start()
            proc = self.run_helper("media", addr_env=stub.addr)
            server.join(5)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(stub.received, b'{"ChangeLayer":{"new":"media"}}\n')
        finally:
            stub.close()

    def test_rejects_unknown_layer_without_connecting(self):
        stub = StubPedal()
        try:
            proc = self.run_helper("volume", addr_env=stub.addr)
            self.assertEqual(proc.returncode, 1, proc.stderr)
            self.assertIn("usage", proc.stderr.lower())
            self.assertEqual(stub.connections, 0)
        finally:
            stub.close()

    def test_rejects_missing_target(self):
        stub = StubPedal()
        try:
            proc = self.run_helper(addr_env=stub.addr)
            self.assertEqual(proc.returncode, 1, proc.stderr)
            self.assertEqual(stub.connections, 0)
        finally:
            stub.close()

    def test_rejects_extra_arguments(self):
        stub = StubPedal()
        try:
            proc = self.run_helper("pages", "media", addr_env=stub.addr)
            self.assertEqual(proc.returncode, 1, proc.stderr)
            self.assertEqual(stub.connections, 0)
        finally:
            stub.close()

    def test_unreachable_endpoint_exits_2(self):
        # Bind then close: the port is a black hole (refused) with no
        # listener racing to accept.
        hole = socket.create_server(("127.0.0.1", 0))
        closed_port = hole.getsockname()[1]
        hole.close()
        proc = self.run_helper("pages", addr_env=f"127.0.0.1:{closed_port}")
        self.assertEqual(proc.returncode, 2, proc.stderr)
        self.assertIn("unreachable", proc.stderr.lower())

    def test_helper_is_executable_with_shebang(self):
        self.assertTrue(os.access(HELPER, os.X_OK), f"not executable: {HELPER}")
        first = HELPER.read_bytes().split(b"\n", 1)[0]
        self.assertTrue(first.startswith(b"#!"), "missing shebang")

    def test_rejects_invalid_endpoint(self):
        for addr in ("", "localhost", "127.0.0.1:wrong", "127.0.0.1:0", "127.0.0.1:65536"):
            with self.subTest(addr=addr):
                proc = self.run_helper("pages", addr_env=addr)
                self.assertEqual(proc.returncode, 1, proc.stderr)
                self.assertNotIn("Traceback", proc.stderr)

    def test_rejects_invalid_timeout(self):
        for timeout in ("wrong", "nan", "inf", "-1", "0", "61"):
            with self.subTest(timeout=timeout):
                proc = self.run_helper("pages", addr_env="127.0.0.1:1", timeout_env=timeout)
                self.assertEqual(proc.returncode, 1, proc.stderr)
                self.assertIn("BLUETURN_SWITCH_TIMEOUT", proc.stderr)
                self.assertNotIn("Traceback", proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
