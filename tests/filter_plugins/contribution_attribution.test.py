#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from contribution_attribution import attribute_bins, attribute_links, attribute_statuses


def test_bin_attribution_unions_existing_origins():
    value = attribute_bins(
        [{"name": "build.sh", "origin_subsystems": ["go"], "contributors": ["site:local"]}],
        "demo-main",
        "rust",
    )
    assert value[0]["contributors"] == [
        "site:local",
        "deployment:demo-main",
        "subsystem:rust",
        "subsystem:go",
    ]


def test_status_shorthand_gets_legacy_identity():
    value = attribute_statuses(["status-links.sh"], "demo-main", "links")
    assert value == [{
        "id": "legacy:status-links.sh",
        "name": "status-links.sh",
        "contributors": ["deployment:demo-main", "subsystem:links"],
    }]


def test_native_status_identity_survives():
    value = attribute_statuses(
        [{"id": "zim-activation", "name": "status-zim.sh", "args": ["--activation-only"]}],
        "zim-main",
        "zim",
    )
    assert value[0]["id"] == "zim-activation"
    assert value[0]["contributors"] == ["deployment:zim-main", "subsystem:zim"]


def test_link_attribution_preserves_domain_record():
    value = attribute_links(
        [{"id": "tool", "src": "/src", "dest": "/dest", "contributors": ["subsystem:go"]}],
        "demo-main",
        "links",
    )
    assert value[0] == {
        "id": "tool",
        "src": "/src",
        "dest": "/dest",
        "contributors": ["subsystem:go", "deployment:demo-main", "subsystem:links"],
    }


def test_string_contributor_and_invalid_status_id():
    assert attribute_links(
        [{"id": "tool", "src": "/src", "dest": "/dest", "contributors": "site:local"}],
        "demo-main",
    )[0]["contributors"] == ["site:local", "deployment:demo-main"]
    try:
        attribute_statuses([{"id": [], "name": "status-tool.sh"}], "demo-main")
    except Exception as error:
        assert "string id" in str(error)
    else:
        raise AssertionError("invalid status id was accepted")
    for invalid in ({"bad": "shape"}, 42):
        try:
            attribute_links(
                [{"id": "tool", "src": "/src", "dest": "/dest", "contributors": invalid}],
                "demo-main",
            )
        except Exception as error:
            assert "contributors" in str(error)
        else:
            raise AssertionError("invalid contributors were accepted")


if __name__ == "__main__":
    test_bin_attribution_unions_existing_origins()
    test_status_shorthand_gets_legacy_identity()
    test_native_status_identity_survives()
    test_link_attribution_preserves_domain_record()
    test_string_contributor_and_invalid_status_id()
    print("ok: contribution attribution")
