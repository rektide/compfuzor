#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError
from artifact_links import artifacts_have_links, compile_artifacts, compile_links


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


def check_raises(label, callback, expected):
    try:
        callback()
    except AnsibleFilterError as error:
        if expected not in str(error):
            raise AssertionError(f"{label}: unexpected error: {error}") from error
    else:
        raise AssertionError(f"{label}: did not raise")
    print(f"ok: {label}")


def context(contained_etc=False):
    result = {
        "DIR": "/srv/watchman-main",
        "NAME": "watchman-main",
        "DIRSET": ["etc", "var", "share"],
        "ETC": "/etc/opt/watchman-main",
        "VAR": "/var/lib/watchman-main",
        "SHARE": "/usr/share/watchman-main",
        "FILES": [
            {"name": "root.txt", "src": "root.txt"},
            {"name": "line.conf", "dest": "../line.conf", "line": "enabled=1"},
        ],
        "ETC_FILES": [
            {"name": "watchman.json", "json": {"enabled": True}, "link": "user"},
            {"name": "absolute", "dest": "~/.config/absolute", "content": "x"},
            {
                "name": "desktop",
                "dest": "generated.desktop",
                "content": "x",
                "links": [
                    {
                        "scope": "user",
                        "dest": {"fsh": "share", "name": "applications/generated.desktop"},
                    }
                ],
            },
        ],
    }
    if contained_etc:
        result.update({
            "FS_ETC_MATERIALIZED_ROOT": "/srv/watchman-main/etc",
            "FS_ETC_EXPOSURE_ROOT": "/etc/opt/watchman-main",
        })
    return result


ROOTS = {
    "system": {
        "etc": "/etc/opt/watchman-main",
        "var": "/var/lib/watchman-main",
        "share": "/usr/share/watchman-main",
    },
    "user": {
        "etc": "${HOME}/.config/watchman-main",
        "var": "${HOME}/.local/var/lib/watchman-main",
        "share": "${HOME}/.local/usr/share/watchman-main",
    },
}


def test_artifacts():
    artifacts = compile_artifacts(context())
    etc = artifacts["families"]["ETC_FILES"]
    check("etc materialized root", etc["materialized_root"], "/etc/opt/watchman-main")
    check("etc exposure root", etc["exposure_root"], "/srv/watchman-main/etc")
    check("relative destination", etc["entries"][0]["resolved_dest"], "/etc/opt/watchman-main/watchman.json")
    check("tilde destination", etc["entries"][1]["resolved_dest"], "~/.config/absolute")
    check("dotdot destination", artifacts["lines"][0]["resolved_dest"], "/srv/watchman-main/../line.conf")
    check("line and copy partition", (len(artifacts["copies"]), len(artifacts["lines"])), (4, 1))
    check("annotation discovery", artifacts_have_links(artifacts), True)

    contained = compile_artifacts(context(contained_etc=True))
    etc = contained["families"]["ETC_FILES"]
    check("explicit materialized root", etc["materialized_root"], "/srv/watchman-main/etc")
    check("explicit exposure root", etc["exposure_root"], "/etc/opt/watchman-main")
    check("explicit materialized source", etc["entries"][0]["resolved_dest"], "/srv/watchman-main/etc/watchman.json")
    check("empty annotation discovery", artifacts_have_links(compile_artifacts({"DIR": "/srv/x", "NAME": "x", "DIRSET": []})), False)


def test_links():
    artifacts = compile_artifacts(context())
    plan = compile_links(
        [
            {
                "id": "system-config",
                "src": "etc/source.conf",
                "dest": "/etc/source.conf",
                "policy": "fail",
            }
        ],
        artifacts,
        "/srv/watchman-main",
        "watchman-main",
        ROOTS,
    )
    links = plan["links"]
    check("manifest version", plan["version"], 2)
    check("manifest location metadata", plan["deployment"]["dir"], "/srv/watchman-main")
    check("explicit source base", links[0]["src"], "/srv/watchman-main/etc/source.conf")
    check("symmetric user destination", links[1]["dest"], "${HOME}/.config/watchman-main/watchman.json")
    check("compiled artifact source", links[1]["src"], "/etc/opt/watchman-main/watchman.json")
    check("runtime roots", links[1]["runtimeRoots"], ["HOME"])
    check("cross-family destination", links[2]["dest"], "${HOME}/.local/usr/share/watchman-main/applications/generated.desktop")
    check("annotation origin", links[2]["origin"]["family"], "ETC_FILES")

    xdg = compile_links(
        [{"src": "${XDG_STATE_HOME}/watchman/user-state", "dest": "${HOME}/legacy"}],
        {"families": {}},
        "/srv/watchman-main",
        "watchman-main",
        ROOTS,
    )["links"][0]
    check("xdg state runtime root", xdg["runtimeRoots"], ["HOME", "XDG_STATE_HOME"])

    represented = compile_links(
        [
            {
                "src": "/source",
                "dest": "/consumer",
                "strategies": {"available": ["link", "copy"], "default": "copy"},
                "compose": False,
            }
        ],
        {"families": {}},
        "/srv/watchman-main",
        "watchman-main",
        ROOTS,
    )["links"][0]
    check("strategy declaration", represented["strategies"], {"available": ["link", "copy"], "default": "copy"})
    check("composition declaration", represented["compose"], False)
    check("ordinary records stay implicit link-only", "strategies" in links[0], False)
    canonical = compile_links(
        [{"src": "/source", "dest": "/consumer", "strategies": {"available": ["copy", "link"], "default": "copy"}}],
        {"families": {}},
        "/srv/watchman-main",
        "watchman-main",
        ROOTS,
    )["links"][0]
    check("strategy set canonical order", canonical["strategies"]["available"], ["link", "copy"])


def test_validation():
    check_raises(
        "destTemplate retired",
        lambda: compile_artifacts({**context(), "ETC_FILES": [{"name": "x", "destTemplate": "/x"}]}),
        "destTemplate",
    )
    check_raises(
        "invalid materialized root",
        lambda: compile_artifacts({**context(), "FS_ETC_MATERIALIZED_ROOT": 42}),
        "FS_ETC_MATERIALIZED_ROOT",
    )
    artifacts = compile_artifacts(context())
    check_raises(
        "mapping LINKS rejected",
        lambda: compile_links({"/x": "/y"}, artifacts, "/srv/watchman-main", "watchman-main", ROOTS),
        "LINKS must be a list",
    )
    check_raises(
        "destination collision",
        lambda: compile_links(
            [
                {"src": "/one", "dest": "/same"},
                {"src": "/two", "dest": "/same"},
            ],
            {"families": {}},
            "/srv/watchman-main",
            "watchman-main",
            ROOTS,
        ),
        "destination",
    )
    check_raises(
        "FILES has no symmetric family",
        lambda: compile_links(
            [],
            compile_artifacts({"DIR": "/srv/x", "NAME": "x", "DIRSET": [], "FILES": [{"name": "x", "link": "user"}]}),
            "/srv/x",
            "x",
            ROOTS,
        ),
        "has no fsh kind",
    )
    check_raises(
        "links requires a list",
        lambda: compile_links(
            [],
            compile_artifacts({
                "DIR": "/srv/x",
                "NAME": "x",
                "DIRSET": ["etc"],
                "ETC": "/etc/opt/x",
                "ETC_FILES": [{"name": "x", "links": {"dest": "/x"}}],
            }),
            "/srv/x",
            "x",
            ROOTS,
        ),
        "links must be a list",
    )
    check_raises(
        "unsupported dollar expression",
        lambda: compile_links(
            [{"src": "/source", "dest": "$HOME/x"}],
            {"families": {}},
            "/srv/x",
            "x",
            ROOTS,
        ),
        "unsupported runtime expression",
    )
    check_raises(
        "scope alone does not infer destination",
        lambda: compile_links(
            [],
            compile_artifacts({
                "DIR": "/srv/x",
                "NAME": "x",
                "DIRSET": ["etc"],
                "ETC": "/etc/opt/x",
                "ETC_FILES": [{"name": "x", "links": [{"scope": "user"}]}],
            }),
            "/srv/x",
            "x",
            ROOTS,
        ),
        "requires dest",
    )
    for label, strategies, expected in (
        ("strategy mapping", ["link"], "strategies must be a mapping"),
        ("strategy availability", {"available": [], "default": "link"}, "non-empty list"),
        ("strategy name", {"available": ["magic"], "default": "magic"}, "only link or copy"),
        ("strategy duplicate", {"available": ["link", "link"], "default": "link"}, "duplicates"),
        ("strategy default", {"available": ["link"], "default": "copy"}, "must be available"),
    ):
        check_raises(
            label,
            lambda strategies=strategies: compile_links(
                [{"src": "/source", "dest": "/dest", "strategies": strategies}],
                {"families": {}},
                "/srv/x",
                "x",
                ROOTS,
            ),
            expected,
        )
    check_raises(
        "compose boolean",
        lambda: compile_links(
            [{"src": "/source", "dest": "/dest", "compose": "no"}],
            {"families": {}},
            "/srv/x",
            "x",
            ROOTS,
        ),
        "compose must be boolean",
    )


if __name__ == "__main__":
    test_artifacts()
    test_links()
    test_validation()
