#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError
from bin_disarm import (  # noqa: E402
    annotate_bins,
    canonical_bin_action,
    resolve_bin_disarm,
)


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


def test_canonicalization():
    check("basename and final shell suffix", canonical_bin_action("a/build-go.sh"), "BUILD_GO")
    check("dot qualifier", canonical_bin_action("install-rust.user.sh"), "INSTALL_RUST")
    check(
        "earlier dot qualifier wins",
        canonical_bin_action("my-script-example.foo-bar.sh"),
        "MY_SCRIPT_EXAMPLE",
    )
    check("punctuation collapses", canonical_bin_action("a---b__c.sh"), "A_B_C")


def test_automatic_resolution_and_scope_subtraction():
    go = resolve_bin_disarm("build-go.sh", ["go"], ["go"])
    check("go action", go["action"], "BUILD")
    check("go automatic entries", go["entries"], ["GO", "GO:BUILD"])
    check("go derived verb", go["verb"], "build")
    check("go report labels", go["report_labels"], "go")

    kernel = resolve_bin_disarm(
        "install-kernel-cmdline.sh", ["kernel_modprobe"], ["kernel"]
    )
    check("kernel action removes broad tokens", kernel["action"], "INSTALL_CMDLINE")
    check(
        "kernel nested action",
        kernel["entries"],
        ["KERNEL", "KERNEL:INSTALL_CMDLINE"],
    )


def test_explicit_extension_false_and_fallback():
    extended = resolve_bin_disarm(
        "build-go.sh",
        ["go", "go"],
        ["go", "go"],
        ["BUILD", "GO", "LINK:SERVICE"],
    )
    check(
        "explicit guards extend and stable-dedupe automatic policy",
        extended["entries"],
        ["GO", "GO:BUILD", "BUILD", "LINK:SERVICE"],
    )
    check("origin labels stable-dedupe", extended["subsystems"], ["go"])

    disabled = resolve_bin_disarm("build-go.sh", ["go"], ["go"], False, "src")
    check("false disables all guards", disabled["entries"], [])

    fallback = resolve_bin_disarm("apply-network.sh", fallback_type="host-tools")
    check(
        "TYPE fallback applies to direct shell bins",
        fallback["entries"],
        ["HOST_TOOLS", "HOST_TOOLS:APPLY_NETWORK"],
    )
    check(
        "TYPE fallback does not apply to non-shell records",
        resolve_bin_disarm("venv.source", fallback_type="python")["entries"],
        [],
    )


def test_annotator_and_errors():
    check(
        "annotator extends metadata without overloading subsystem",
        annotate_bins(
            [{"name": "build.sh", "origin_subsystems": ["base"]}],
            "kernel_sysctl",
            "kernel",
            subsystem="kernel",
        ),
        [
            {
                "name": "build.sh",
                "origin_subsystems": ["base", "kernel_sysctl"],
                "bypass_scopes": ["kernel"],
                "subsystem": "kernel",
            }
        ],
    )
    try:
        resolve_bin_disarm("build.sh", bypass={"bad": "shape"})
    except AnsibleFilterError as error:
        check("clear unusable-shape error", "string or list" in str(error), True)
    else:
        raise AssertionError("mapping bypass should fail")


if __name__ == "__main__":
    test_canonicalization()
    test_automatic_resolution_and_scope_subtraction()
    test_explicit_extension_false_and_fallback()
    test_annotator_and_errors()
