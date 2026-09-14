#!/usr/bin/env python3

import os
import sys

sys.path.insert(0, "library/lookup_plugins")

from ansible.errors import AnsibleError
from playbook_identity import resolve_playbook_identity


def test_exact_cli_identity():
    value = resolve_playbook_identity(
        {"NAME": "zim-main", "TYPE": "zim", "INSTANCE": "main", "DIR": "/opt/zim-main"},
        cliargs={"args": ["zim.opt.pb"]},
    )
    assert value["id"] == "deployment:zim-main"
    assert value["name"] == "zim-main"
    assert value["type"] == "zim"
    assert value["source"] == {
        "resolution": "ansible-cliargs",
        "confidence": "exact",
        "candidates": [os.path.abspath("zim.opt.pb")],
        "playbook": os.path.abspath("zim.opt.pb"),
    }


def test_ambiguous_cli_identity_keeps_candidates():
    value = resolve_playbook_identity(
        {"NAME": "combined"},
        cliargs={"args": ["one.opt.pb", "two.srv.pb"]},
    )
    assert value["source"]["confidence"] == "ambiguous"
    assert value["source"]["candidates"] == [
        os.path.abspath("one.opt.pb"),
        os.path.abspath("two.srv.pb"),
    ]
    assert "playbook" not in value["source"]


def test_explicit_source_wins():
    value = resolve_playbook_identity(
        {"NAME": "explicit", "COMPFUZOR_PLAYBOOK_PATH": "chosen.pb"},
        cliargs={"args": ["ignored.pb"]},
    )
    assert value["source"]["resolution"] == "explicit"
    assert value["source"]["playbook"] == os.path.abspath("chosen.pb")


def test_legacy_and_unknown_sources():
    legacy = resolve_playbook_identity(
        {"NAME": "legacy"},
        cliargs={},
        cmdline="ansible-playbook\0legacy.opt.pb\0",
    )
    assert legacy["source"]["resolution"] == "legacy-cmdline"
    assert legacy["source"]["confidence"] == "exact"
    unknown = resolve_playbook_identity({"NAME": "unknown"}, cliargs={}, cmdline="")
    assert unknown["source"]["confidence"] == "unknown"


def test_name_is_required():
    try:
        resolve_playbook_identity({}, cliargs={"args": ["test.pb"]})
    except AnsibleError as error:
        assert "NAME" in str(error)
    else:
        raise AssertionError("missing NAME was accepted")


if __name__ == "__main__":
    test_exact_cli_identity()
    test_ambiguous_cli_identity_keeps_candidates()
    test_explicit_source_wins()
    test_legacy_and_unknown_sources()
    test_name_is_required()
    print("ok: playbook identity")
