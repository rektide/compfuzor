#!/usr/bin/env python3
"""Standalone apt deb822 renderer tests: python tests/filter_plugins/apt_sources.test.py."""
import sys

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError  # noqa: E402
from apt_sources import apt_preferences, apt_sources  # noqa: E402


def fails(fn, *args):
    try:
        fn(*args)
    except AnsibleFilterError:
        return
    raise AssertionError("expected invalid apt declaration")


def test_sources():
    result = apt_sources(
        [{"URIs": "https://example.org", "By-Hash": "yes", "architectures": ["amd64", "arm64"]},
         {"URIs": "https://flat.example/", "Suites": "/", "Components": [], "Types": ["deb", "deb-src"], "Signed-By": "/keys/other.gpg"}],
        {"Types": "deb", "Suites": "forky", "Components": "main"}, "/keys/default.gpg",
    )
    assert result == (
        "Types: deb\nSuites: forky\nComponents: main\nSigned-By: /keys/default.gpg\n"
        "URIs: https://example.org\nBy-Hash: yes\nArchitectures: amd64 arm64\n\n"
        "Types: deb deb-src\nSuites: /\nSigned-By: /keys/other.gpg\n"
        "URIs: https://flat.example/\n"
    )
    assert "Signed-By" not in apt_sources([{"URIs": "https://example.org"}], {"Suites": "forky"})
    assert "Enabled: no" in apt_sources([{"URIs": "https://example.org", "Enabled": False}], {"Suites": "forky"})
    assert "Trusted: no" in apt_sources([{"URIs": "https://example.org", "Trusted": False}], {"Suites": "forky"})
    fails(apt_sources, [{}], {"Suites": "forky"})
    fails(apt_sources, [], {})
    fails(apt_sources, [{"URIs": "u", "Bad:Field": "x"}], {"Suites": "s"})
    fails(apt_sources, [{"URIs": "u\nEnabled: no"}], {"Suites": "s"})


def test_inline_key_and_pins():
    key = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nabc\n-----END PGP PUBLIC KEY BLOCK-----\n"
    result = apt_sources([{"URIs": "https://example.org", "Signed-By": key}], {"Suites": "stable"})
    assert "Signed-By:\n -----BEGIN PGP PUBLIC KEY BLOCK-----\n .\n abc\n -----END PGP PUBLIC KEY BLOCK-----" in result
    assert apt_preferences({"Pin": "release n=stable", "Pin-Priority": 600}) == (
        "Package: *\nPin: release n=stable\nPin-Priority: 600\n"
    )
    fails(apt_preferences, {"Pin": "release n=stable"})


if __name__ == "__main__":
    test_sources()
    test_inline_key_and_pins()
    print("ok: apt deb822 rendering")
