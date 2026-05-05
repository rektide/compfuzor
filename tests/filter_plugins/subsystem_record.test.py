#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'library', 'filter_plugins'))

from build_install_bins import build_install_bins

passed = 0
failed = 0


def check(name, actual, expected):
    global passed, failed
    if actual == expected:
        passed += 1
        print("  PASS: {}".format(name))
    else:
        failed += 1
        print("  FAIL: {}".format(name))
        print("    actual:   {}".format(actual))
        print("    expected: {}".format(expected))


def test_build_install_bins_normal():
    print("\nbuild_install_bins: normal stem")
    result = build_install_bins("sysctl")
    expected = {
        "build_bins": [
            {"name": "build-sysctl.sh", "src": "../kernel/build-sysctl.sh", "basedir": False}
        ],
        "install_bins": [
            {"name": "install-sysctl.sh", "src": "../kernel/install-sysctl.sh", "basedir": False}
        ],
    }
    check("normal stem produces correct entries", result, expected)


def test_build_install_bins_empty():
    print("\nbuild_install_bins: empty stem")
    result = build_install_bins("")
    check("empty stem returns empty lists", result, {"build_bins": [], "install_bins": []})


def test_build_install_bins_basedir():
    print("\nbuild_install_bins: basedir=True")
    result = build_install_bins("kernel", basedir=True)
    check(
        "basedir flag forwarded",
        result["build_bins"][0]["basedir"],
        True,
    )
    check(
        "install basedir forwarded",
        result["install_bins"][0]["basedir"],
        True,
    )


def test_build_install_bins_custom_src_root():
    print("\nbuild_install_bins: custom src_root")
    result = build_install_bins("foo", src_root="/custom")
    check(
        "build src uses custom root",
        result["build_bins"][0]["src"],
        "/custom/build-foo.sh",
    )
    check(
        "install src uses custom root",
        result["install_bins"][0]["src"],
        "/custom/install-foo.sh",
    )


if __name__ == "__main__":
    test_build_install_bins_normal()
    test_build_install_bins_empty()
    test_build_install_bins_basedir()
    test_build_install_bins_custom_src_root()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
