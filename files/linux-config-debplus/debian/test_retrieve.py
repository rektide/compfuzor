#!/usr/bin/env python3
"""Focused metadata/config tests; no network or host configuration writes."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("retrieve", Path(__file__).with_name("retrieve.py"))
retrieve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retrieve)


class RetrievalTests(unittest.TestCase):
    def test_folded_metadata(self):
        result = list(retrieve.records("Package: a\nDepends: b,\n c (= 1)\n\nPackage: d\nVersion: 2\n"))
        self.assertEqual(result[0]["Depends"], "b,\nc (= 1)")
        self.assertEqual(result[1]["Package"], "d")

    def test_meta_exact_dependency_beats_later_unreferenced_headers(self):
        selected, meta, _ = retrieve.select_package([
            {"Package": "linux-headers-amd64", "Version": "7.2.8-1", "Depends": "linux-base-amd64 (= 7.2.8-1), linux-headers-7.2.8+deb14-amd64 (= 7.2.8-1)"},
            {"Package": "linux-headers-7.2.8+deb14-amd64", "Version": "7.2.8-1"},
            {"Package": "linux-headers-7.3-amd64", "Version": "7.3-1"},
        ])
        self.assertEqual(selected["Version"], "7.2.8-1")
        self.assertEqual(meta["Package"], "linux-headers-amd64")

    def test_fallback_uses_debian_not_lexical_versions_and_excludes_flavours(self):
        selected, meta, _ = retrieve.select_package([
            {"Package": "linux-headers-7.2.9-amd64", "Version": "7.2.9-1"},
            {"Package": "linux-headers-7.2.10-amd64", "Version": "7.2.10-1"},
            {"Package": "linux-headers-7.3-rt-amd64", "Version": "7.3-1"},
            {"Package": "linux-headers-7.3-cloud-amd64", "Version": "7.3-1"},
        ])
        self.assertEqual(selected["Version"], "7.2.10-1")
        self.assertIsNone(meta)

    def test_experimental_absence_is_not_unstable_fallback(self):
        self.assertEqual(retrieve.select_package([])[:2], (None, None))

    def test_incomplete_meta_fails(self):
        with self.assertRaises(ValueError):
            retrieve.select_package([{"Package": "linux-headers-amd64", "Version": "1", "Depends": "missing"}])

    def test_checksum_failure(self):
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            retrieve.checked(b"corrupt", retrieve.sha(b"expected"))

    def test_index_release_checksum(self):
        digest = "a" * 64
        self.assertEqual(retrieve.release_index(f"SHA256:\n {digest} 42 main/binary-amd64/Packages.xz\nDate: now\n".encode()), (digest, 42))

    def test_absence_is_not_disabled_and_metadata_is_not_policy(self):
        before = retrieve.parse_config('CONFIG_GCC_VERSION=160000\n# CONFIG_RUST is not set\n')
        after = retrieve.parse_config('CONFIG_GCC_VERSION=0\nCONFIG_RUST=y\nCONFIG_NEW=y\n')
        self.assertEqual(retrieve.delta(before, after, exclude_metadata=True), "NEW: <absent> -> y\nRUST: n -> y\n")

    def test_required_intent_distinguishes_inherited_match_and_missing_value(self):
        result = retrieve.required_audit({"RUST": "y", "DEBUG_INFO_BTF": "y"}, {"RUST": "y"}, {})
        self.assertTrue(result["RUST"]["fulfilled"])
        self.assertEqual(result["RUST"]["declaration"], "inherited/not explicitly declared")
        self.assertFalse(result["DEBUG_INFO_BTF"]["fulfilled"])

    def test_merge_replaces_prior_assignments_without_duplicate_symbols(self):
        text = retrieve.merged_config("CONFIG_X=y\nCONFIG_Y=m\n", "# CONFIG_X is not set\nCONFIG_Z=y\n")
        self.assertEqual(retrieve.parse_config(text), {"X": "n", "Y": "m", "Z": "y"})
        self.assertEqual(len(text.splitlines()), 3)

    def test_debug_info_is_derived_from_declared_selectable_choice(self):
        result = retrieve.required_audit({"DEBUG_INFO": "y"}, {"DEBUG_INFO": "y"},
                                        {"DEBUG_KERNEL": "y", "DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT": "y"})
        self.assertTrue(result["DEBUG_INFO"]["fulfilled"])
        self.assertEqual(result["DEBUG_INFO"]["declaration"], "derived from explicitly declared debug-information choice")

    def test_kernel_export_does_not_inherit_parent_repository_head(self):
        scratch = Path.cwd() / ".test-agent" / "linux-debian-retrieval" / "git-provenance-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            repository = Path(directory) / "parent-repository"
            repository.mkdir()
            subprocess.run(["git", "init", "-q", str(repository)], check=True)
            subprocess.run(["git", "-C", str(repository), "-c", "user.name=Config audit test",
                            "-c", "user.email=config-audit@example.invalid", "commit", "-q", "--allow-empty",
                            "-m", "Fixture parent HEAD"], check=True)
            expected = subprocess.check_output(["git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip()
            export = repository / "plain-kernel-export"
            export.mkdir()
            self.assertEqual(retrieve.kernel_git_head(repository), expected)
            self.assertIsNone(retrieve.kernel_git_head(export))
            alias = Path(directory) / "repository-alias"
            alias.symlink_to(repository, target_is_directory=True)
            self.assertEqual(retrieve.kernel_git_head(alias), expected)


if __name__ == "__main__":
    unittest.main()
