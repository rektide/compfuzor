#!/usr/bin/env python3

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError
import runtime_bundles
from runtime_bundles import links_runtime_bins, links_runtime_dirs


def test_links_runtime_bundles():
    delivery = links_runtime_bins(False)
    assert delivery == []
    full = links_runtime_bins(True)
    assert [record["name"] for record in full] == ["links/links.mjs", "links.mjs"]
    assert full[0]["raw"] and full[0]["compose"] is False
    assert full[0]["src"].endswith("/build/runtime/links/links.mjs")
    assert full[1]["link"] == "links/links.mjs"
    assert links_runtime_dirs("/opt/app/bin") == ["/opt/app/bin/links"]
    full[0]["name"] = "changed"
    assert links_runtime_bins(True)[0]["name"] == "links/links.mjs"

    try:
        links_runtime_bins("full")
    except AnsibleFilterError as error:
        assert "boolean" in str(error)
    else:
        raise AssertionError("non-boolean bundle selector was accepted")

    repository = runtime_bundles._REPOSITORY
    try:
        with tempfile.TemporaryDirectory() as temporary:
            runtime_bundles._REPOSITORY = Path(temporary)
            try:
                runtime_bundles.runtime_artifact_bin("missing.mjs", "missing.mjs")
            except AnsibleFilterError as error:
                assert "pnpm build" in str(error)
            else:
                raise AssertionError("missing built runtime was accepted")
    finally:
        runtime_bundles._REPOSITORY = repository


if __name__ == "__main__":
    test_links_runtime_bundles()
    print("ok: LINKS runtime bundles")
