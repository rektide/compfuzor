#!/usr/bin/env python3
"""Permission decisions for named groups and missing child directories."""
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, "library/filter_plugins")

import can_write
from become import resolve_become


class PermissionTests(unittest.TestCase):
    def setUp(self):
        groups = {"test-user": 61019, "other-user": 61020}

        def lookup(name):
            return SimpleNamespace(gr_gid=groups[name])

        self.group_lookup = patch.object(can_write.grp, "getgrnam", side_effect=lookup)
        self.group_lookup.start()
        self.addCleanup(self.group_lookup.stop)

    def test_named_group_resolves_to_its_gid(self):
        self.assertEqual(can_write.to_gid("test-user"), 61019)
        self.assertEqual(can_write.to_gid(61019), 61019)
        self.assertEqual(can_write.to_gid("missing-group"), -1)

    def test_named_and_numeric_same_group_do_not_differ(self):
        self.assertFalse(can_write.diff_user(61019, 61019, "test-user", 61019))
        self.assertFalse(can_write.diff_user(61019, 61019, 61019, "test-user"))

    def test_distinct_named_groups_differ(self):
        self.assertTrue(can_write.diff_user(61019, 61019, "test-user", "other-user"))

    def resolve_missing_child(self, writable, group=None):
        child = "/home/test-user/src/new-deployment"
        parent = "/home/test-user/src"

        def access(path, mode):
            if mode == can_write.os.F_OK:
                return path == parent
            self.assertEqual((path, mode), (parent, can_write.os.W_OK))
            return writable

        with patch.object(can_write.os, "access", side_effect=access):
            return resolve_become(
                {"OWNER": 61019, "GROUP": group,
                 "_cf_user_id": 61019, "_cf_user_gid": 61019},
                child,
            )["become"]

    def test_missing_child_under_writable_parent_needs_no_become(self):
        self.assertFalse(self.resolve_missing_child(True))

    def test_matching_named_group_on_writable_parent_needs_no_become(self):
        self.assertFalse(self.resolve_missing_child(True, "test-user"))

    def test_unwritable_parent_requires_become_even_with_matching_identity(self):
        self.assertTrue(self.resolve_missing_child(False))
        self.assertTrue(self.resolve_missing_child(False, "test-user"))


if __name__ == "__main__":
    unittest.main()
