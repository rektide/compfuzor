#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError
from runtime_bundles import links_runtime_bins, links_runtime_dirs


def test_links_runtime_bundles():
    delivery = links_runtime_bins(False)
    assert [record["name"] for record in delivery] == ["links/delivery.ts"]
    full = links_runtime_bins(True)
    assert [record["name"] for record in full] == ["links.ts", "links/links.ts", "links/cli.ts", "links/manifest.ts", "links/delivery.ts"]
    assert all(record["raw"] and record["compose"] is False for record in full)
    assert links_runtime_dirs("/opt/app/bin") == ["/opt/app/bin/links"]
    delivery[0]["name"] = "changed"
    assert links_runtime_bins(False)[0]["name"] == "links/delivery.ts"

    try:
        links_runtime_bins("full")
    except AnsibleFilterError as error:
        assert "boolean" in str(error)
    else:
        raise AssertionError("non-boolean bundle selector was accepted")


if __name__ == "__main__":
    test_links_runtime_bundles()
    print("ok: LINKS runtime bundles")
