#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError  # noqa: E402
from sysusers import sysusers_render  # noqa: E402


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


def raises(label, fn, *args):
    try:
        fn(*args)
    except AnsibleFilterError:
        print(f"ok: {label} raises")
        return
    raise AssertionError(f"{label}: expected AnsibleFilterError")


def test_string_shorthand():
    check(
        "string shorthand -> default u line",
        sysusers_render(["apt-cacher-rs"]),
        'u apt-cacher-rs - "apt-cacher-rs" /nonexistent /usr/sbin/nologin\n',
    )


def test_mapping_overrides():
    check(
        "attribute overrides",
        sysusers_render(
            [
                {
                    "name": "gitea",
                    "comment": "Gitea daemon",
                    "home": "/var/lib/gitea",
                    "shell": "/bin/bash",
                }
            ]
        ),
        'u gitea - "Gitea daemon" /var/lib/gitea /bin/bash\n',
    )


def test_kinds():
    check(
        "group + member forms",
        sysusers_render(
            [
                {"name": "media", "kind": "group"},
                "sonarr",
                {"name": "sonarr", "member": "media"},
                {"name": "rektide", "kind": "member", "group": "media"},
            ]
        ),
        "g media -\nu sonarr - \"sonarr\" /nonexistent /usr/sbin/nologin\nm sonarr media\nm rektide media\n",
    )


def test_dependency_safe_order():
    check(
        "authoring order does not matter (g before u before m)",
        sysusers_render(
            [
                {"name": "sonarr", "member": "media"},
                "sonarr",
                {"name": "media", "kind": "group"},
            ]
        ),
        "g media -\nu sonarr - \"sonarr\" /nonexistent /usr/sbin/nologin\nm sonarr media\n",
    )


def test_same_name_override():
    check(
        "later u spec wins outright (authored overrides derived)",
        sysusers_render(
            [
                {"name": "apt-cacher-rs", "comment": "apt-cacher-rs-git daemon"},
                {"name": "apt-cacher-rs", "home": "/var/lib/apt-cacher-rs"},
            ]
        ),
        'u apt-cacher-rs - "apt-cacher-rs" /var/lib/apt-cacher-rs /usr/sbin/nologin\n',
    )


def test_membership_dedupe_and_independence():
    check(
        "identical m lines dedupe, user+membership coexist",
        sysusers_render(
            [
                {"name": "sonarr", "member": "media"},
                "sonarr",
                {"name": "sonarr", "member": "media"},
            ]
        ),
        'u sonarr - "sonarr" /nonexistent /usr/sbin/nologin\nm sonarr media\n',
    )


def test_gecos_quoting():
    check(
        "comment quoting escapes backslash and double quote",
        sysusers_render([{"name": "demo", "comment": 'says "hi" \\ ok'}]),
        'u demo - "says \\"hi\\" \\\\ ok" /nonexistent /usr/sbin/nologin\n',
    )


def test_uid_gid_field():
    check(
        "explicit id fields",
        sysusers_render([{"name": "pin", "id": "999"}, {"name": "pg", "kind": "group", "id": "998"}]),
        "g pg 998\nu pin 999 \"pin\" /nonexistent /usr/sbin/nologin\n",
    )


def test_empty():
    check("no specs -> empty body", sysusers_render([]), "")
    check("undefined -> empty body", sysusers_render(None), "")


def test_errors():
    raises("empty name", sysusers_render, [{"name": ""}])
    raises("bad name", sysusers_render, [{"name": "bad name!"}])
    raises("bad kind", sysusers_render, [{"name": "x", "kind": "robot"}])
    raises("member without group", sysusers_render, [{"name": "x", "kind": "member"}])
    raises("bad member group", sysusers_render, [{"name": "x", "member": "not a group"}])
    raises("relative home", sysusers_render, [{"name": "x", "home": "var/lib/x"}])
    raises("non-mapping spec", sysusers_render, [42])


def main():
    test_string_shorthand()
    test_mapping_overrides()
    test_kinds()
    test_dependency_safe_order()
    test_same_name_override()
    test_membership_dedupe_and_independence()
    test_gecos_quoting()
    test_uid_gid_field()
    test_empty()
    test_errors()
    print("all sysusers_render checks passed")


if __name__ == "__main__":
    main()
