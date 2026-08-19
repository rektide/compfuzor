#!/usr/bin/env python3

import os
import sys

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "library", "lookup_plugins"
    ),
)

from ansible.errors import AnsibleError

from fsh import LookupModule

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


def check_raises(name, fn, text):
    global passed, failed
    try:
        fn()
    except AnsibleError as error:
        if text in str(error):
            passed += 1
            print("  PASS: {}".format(name))
        else:
            failed += 1
            print("  FAIL: {}".format(name))
            print("    error: {}".format(error))
    else:
        failed += 1
        print("  FAIL: {} (did not raise)".format(name))


class FakeTemplateEngine:
    def __init__(self, values=None):
        self.values = values or {}
        self.available_variables = None

    def template(self, value):
        return self.values.get(str(value), value)


def run_fsh(variables, terms, **kwargs):
    lookup = LookupModule()
    lookup._templar = FakeTemplateEngine()
    return lookup.run(terms, variables, **kwargs)


def one(variables, term, **kwargs):
    return run_fsh(variables, term, **kwargs)[0]


BASE = {
    "VARS_DIR": "/var/lib",
    "ETCS_DIR": "/etc/opt",
    "SRVS_DIR": "/srv",
    "PIDS_DIR": "/var/run",
    "BINS_DIR": "/srv/watchman-main/bin",
    "HOMEDIR": "/home/rektide",
    "NAME": "watchman-main",
    "USERMODE_VARS_DIR": "{{HOMEDIR}}/.local/var/lib",
    "USERMODE_ETCS_DIR": "{{HOMEDIR}}/.config",
    "VAR": "/var/lib/watchman-main",
    "ETC": "/etc/opt/watchman-main",
}

TPL = {
    "{{HOMEDIR}}/.local/var/lib": "/home/rektide/.local/var/lib",
    "{{HOMEDIR}}/.config": "/home/rektide/.config",
    "{{HOMEDIR}}": "/home/rektide",
    "NAME": "watchman-main",
}

V = dict(BASE)
T = dict(TPL)


def with_vars(**extra):
    merged = dict(BASE)
    merged.update(extra)
    return merged


print("fsh lookup: plain (deploy-mode) resolution")
check("var", one(V, "var"), "/var/lib")
check("etc alias plural", one(V, "etcs"), "/etc/opt")
check("var name=True prefers frozen VAR", one(V, "var", name=True), "/var/lib/watchman-main")
check("srv name=True computes when SRV unfrozen", one(V, "srv", name=True), "/srv/watchman-main")

print("fsh lookup: user=True (resolved for deploying user)")
check(
    "var user=True returns USERMODE var (untemplated)",
    run_fsh(V, "var", user=True)[0],
    "{{HOMEDIR}}/.local/var/lib",
)
lookup = LookupModule()
lookup._templar = FakeTemplateEngine(T)
check(
    "var user=True templated",
    lookup.run("var", V, user=True)[0],
    "/home/rektide/.local/var/lib",
)
lookup._templar = FakeTemplateEngine(T)
check(
    "var user=True name=True",
    lookup.run("var", V, user=True, name=True)[0],
    "/home/rektide/.local/var/lib/watchman-main",
)

print("fsh lookup: USER_FSH flip (specifier source)")
lookup._templar = FakeTemplateEngine(T)
check(
    "var name=True under USER_FSH",
    lookup.run("var", with_vars(USER_FSH=True), name=True)[0],
    "%h/.local/var/lib/watchman-main",
)
check(
    "pid name=True under USER_FSH",
    lookup.run("pid", with_vars(USER_FSH=True), name=True)[0],
    "%t/watchman-main",
)
check(
    "bins under USER_FSH falls back to system dir",
    lookup.run("bins", with_vars(USER_FSH=True))[0],
    "/srv/watchman-main/bin",
)
check(
    "global-bins under USER_FSH",
    lookup.run("global-bins", with_vars(USER_FSH=True))[0],
    "%h/.local/bin",
)
check(
    "_fsh_user reserved flip",
    lookup.run("var", with_vars(_fsh_user=True), name=True)[0],
    "%h/.local/var/lib/watchman-main",
)
check(
    "_fsh_user truthy string flip",
    lookup.run("var", with_vars(_fsh_user="True"), name=True)[0],
    "%h/.local/var/lib/watchman-main",
)
check(
    "USER_FSH_DIRS override",
    lookup.run("var", with_vars(USER_FSH=True, USER_FSH_DIRS={"var": "%h/state"}))[0],
    "%h/state",
)
check(
    "USER_FSH mapping itself overrides",
    lookup.run("var", with_vars(USER_FSH={"var": "%h/custom-var"}))[0],
    "%h/custom-var",
)
check(
    "falsy USER_FSH does not flip",
    lookup.run("var", with_vars(USER_FSH=False), name=True)[0],
    "/var/lib/watchman-main",
)

print("fsh lookup: multi-term")
check(
    "multi-term order",
    run_fsh(V, ["var", "etc"], user=False),
    ["/var/lib", "/etc/opt"],
)

print("fsh lookup: errors")
check_raises(
    "unknown kind",
    lambda: one(V, "bogus"),
    "unknown kind 'bogus'",
)
check_raises(
    "name=True without NAME",
    lambda: one({k: v for k, v in V.items() if k not in ("NAME", "VAR")}, "var", name=True),
    "NAME is not defined",
)
check_raises(
    "system dir var missing",
    lambda: one({"NAME": "x"}, "var"),
    "'VARS_DIR' is not defined",
)

print("")
print("passed: {}  failed: {}".format(passed, failed))
sys.exit(1 if failed else 0)
