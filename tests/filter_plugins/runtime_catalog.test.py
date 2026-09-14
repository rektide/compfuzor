#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from runtime_catalog import compile_runtime_catalog


def test_runtime_catalog_compiles_attributed_legacy_flows():
    result = compile_runtime_catalog(
        {
            "id": "deployment:demo-main",
            "kind": "deployment",
            "name": "demo-main",
            "source": {"confidence": "exact", "playbook": "/src/demo.opt.pb"},
        },
        [
            {
                "name": "install-tool.sh",
                "phase": "main",
                "contributors": ["deployment:demo-main", "subsystem:rust"],
            },
            {
                "name": "install-rust.sh",
                "generated_by": "gen_bins",
                "run_all": ["install-tool.sh"],
                "contributors": ["deployment:demo-main"],
            },
            {
                "name": "install.sh",
                "generated_by": "gen_bins",
                "run_all": ["install-rust.sh"],
                "contributors": ["deployment:demo-main"],
            },
            {
                "name": "status-tool.sh",
                "contributors": ["deployment:demo-main", "subsystem:rust"],
            },
        ],
        [
            {
                "id": "tool",
                "name": "status-tool.sh",
                "contributors": ["deployment:demo-main", "subsystem:rust"],
            }
        ],
        links_plan={
            "version": 2,
            "links": [
                {
                    "id": "tool",
                    "contributors": ["deployment:demo-main", "subsystem:rust"],
                }
            ],
        },
        subsystems={"config": {"spec": {"version": 2}}},
        etc_files=[{"name": "zim.spec.json"}],
    )
    catalog = result["catalog"]
    assert catalog["execution"] == {"authority": "legacy-shell", "catalogOnly": True}
    assert [item["id"] for item in catalog["contributors"]] == [
        "deployment:demo-main",
        "subsystem:rust",
    ]
    rust = catalog["contributors"][1]
    assert rust["contributions"] == {"BINS": 2, "STATUSES": 1, "LINKS": 1}
    assert [item["contract"] for item in catalog["resources"]] == [
        "compfuzor.config/v2",
        "compfuzor.zim/v2",
        "compfuzor.links/v2",
    ]
    files = {item["name"]: item["invocation"] for item in result["files"]}
    install = files["40-install-001-install-rust-sh.json"]
    assert install["flow"] == "install"
    assert install["invoke"]["action"] == "command:install-rust.sh"
    assert install["contributors"] == ["deployment:demo-main", "subsystem:rust"]
    assert not any("install-tool-sh" in name for name in files)
    status = files["50-status-001-tool.json"]
    assert status["invoke"]["handler"]["protocol"] == "legacy-status-v1"
    assert result["etc_files"][0]["name"] == "compfuzor-runtime/catalog.json"
    assert result["etc_files"][1]["name"].startswith(
        "compfuzor-runtime/workflows/compiled/"
    )
    assert result["etc_dirs"][-1] == "compfuzor-runtime/workflows/site"

    scalar_args = compile_runtime_catalog(
        {"id": "deployment:demo", "name": "demo"},
        [],
        [{"id": "json", "name": "status-json.sh", "args": "--json"}],
    )
    assert scalar_args["files"][0]["invocation"]["invoke"]["args"] == ["--json"]


if __name__ == "__main__":
    test_runtime_catalog_compiles_attributed_legacy_flows()
    print("ok: runtime catalog compiler")
