#!/usr/bin/env python3

import os
import re
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
        self.available_variables = {}

    def template(self, value):
        if not isinstance(value, str):
            return value
        if value in self.values:
            return self.values[value]

        def sub(match):
            key = match.group(1).strip()
            if key in self.available_variables:
                return str(self.available_variables[key])
            return match.group(0)

        return re.sub(r"\{\{\s*(\w+)\s*\}\}", sub, value)


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
    "XDG_RUNTIME_DIR": "/run/user/1000",
    "NAME": "watchman-main",
    "USERMODE_VARS_DIR": "{{HOMEDIR}}/.local/var/lib",
    "USERMODE_ETCS_DIR": "{{HOMEDIR}}/.config",
    "VAR": "/var/lib/watchman-main",
}

print("fsh lookup: plain (deploy-mode) resolution")
check("var", one(BASE, "var"), "/var/lib")
check("etc alias plural", one(BASE, "etcs"), "/etc/opt")
check("var name=True prefers frozen VAR", one(BASE, "var", name=True), "/var/lib/watchman-main")
check("srv name=True computes when SRV unfrozen", one(BASE, "srv", name=True), "/srv/watchman-main")

print("fsh lookup: user=True resolved (USERMODE family parity)")
check(
    "var user=True resolves USERMODE var",
    one(BASE, "var", user=True),
    "/home/rektide/.local/var/lib",
)
check(
    "var user=True name=True",
    one(BASE, "var", user=True, name=True),
    "/home/rektide/.local/var/lib/watchman-main",
)
check(
    "pid user=True resolves XDG_RUNTIME_DIR (no USERMODE pid var)",
    one(BASE, "pid", user=True, name=True),
    "/run/user/1000/watchman-main",
)

print("fsh lookup: home=/runtime= parameters (un-resolved, composable)")
check(
    "var user=True home=%h",
    one(BASE, "var", user=True, name=True, home="%h"),
    "%h/.local/var/lib/watchman-main",
)
check(
    "var user=True home=${HOME} (shell runtime expansion)",
    one(BASE, "var", user=True, name=True, home="${HOME}"),
    "${HOME}/.local/var/lib/watchman-main",
)
check(
    "etc user=True home=%h",
    one(BASE, "etc", user=True, name=True, home="%h"),
    "%h/.config/watchman-main",
)
check(
    "pid user=True runtime=%t",
    one(BASE, "pid", user=True, name=True, runtime="%t"),
    "%t/watchman-main",
)
check(
    "pid user=True runtime=${XDG_RUNTIME_DIR}",
    one(BASE, "pid", user=True, name=True, runtime="${XDG_RUNTIME_DIR}"),
    "${XDG_RUNTIME_DIR}/watchman-main",
)
check(
    "home= parameterizes even without USERMODE parity (spool)",
    one(BASE, "spool", user=True, home="%h"),
    "%h/.local/var/spool",
)
check(
    "global-bins user=True home=%h",
    one(BASE, "global-bins", user=True, home="%h"),
    "%h/.local/bin",
)
check(
    "bins has no user form: falls back to deploy-mode base",
    one(BASE, "bins", user=True, home="%h"),
    "/srv/watchman-main/bin",
)

print("fsh lookup: USER_FSH flip")
check(
    "USER_FSH string flips + supplies home",
    one(dict(BASE, USER_FSH="%h"), "var", name=True),
    "%h/.local/var/lib/watchman-main",
)
check(
    "USER_FSH=${HOME} flips for shell-side use",
    one(dict(BASE, USER_FSH="${HOME}"), "var", name=True),
    "${HOME}/.local/var/lib/watchman-main",
)
check(
    "USER_FSH mapping home/runtime",
    one(dict(BASE, USER_FSH={"home": "${HOME}", "runtime": "${XDG_RUNTIME_DIR}"}), "pid", name=True),
    "${XDG_RUNTIME_DIR}/watchman-main",
)
check(
    "truthy bool USER_FSH flips with resolved home",
    one(dict(BASE, USER_FSH=True), "var", name=True),
    "/home/rektide/.local/var/lib/watchman-main",
)
check(
    "falsy USER_FSH does not flip",
    one(dict(BASE, USER_FSH=False), "var", name=True),
    "/var/lib/watchman-main",
)

print("fsh lookup: USER_FSH_DIRS template overrides")
check(
    "override template may reference {{fsh_home}}",
    one(dict(BASE, USER_FSH_DIRS={"var": "{{fsh_home}}/state"}), "var", user=True, home="%h"),
    "%h/state",
)
check(
    "USER_FSH mapping dirs table",
    one(dict(BASE, USER_FSH={"home": "%h", "dirs": {"var": "{{fsh_home}}/custom"}}), "var", name=True),
    "%h/custom/watchman-main",
)

print("fsh lookup: reserved _fsh_* loop variables")
check(
    "_fsh_user=True + _fsh_home=%h (separate-mode user iteration)",
    one(dict(BASE, _fsh_user=True, _fsh_home="%h", _fsh_runtime="%t"), "var", user=True, name=True),
    "%h/.local/var/lib/watchman-main",
)
check(
    "_fsh_user=False forces system hierarchy over user=True (system iteration)",
    one(dict(BASE, _fsh_user=False, _fsh_home="", _fsh_runtime=""), "var", user=True, name=True),
    "/var/lib/watchman-main",
)
check(
    "lazy template _fsh_user string renders",
    one(dict(BASE, flipvar=True, _fsh_user="{{ flipvar }}", _fsh_home="%h"), "var", name=True),
    "%h/.local/var/lib/watchman-main",
)

print("fsh lookup: multi-term")
check(
    "multi-term order",
    run_fsh(BASE, ["var", "etc"], user=False),
    ["/var/lib", "/etc/opt"],
)

print("fsh lookup: errors")
check_raises(
    "unknown kind",
    lambda: one(BASE, "bogus"),
    "unknown kind 'bogus'",
)
check_raises(
    "name=True without NAME",
    lambda: one({k: v for k, v in BASE.items() if k not in ("NAME", "VAR")}, "var", name=True),
    "NAME is not defined",
)
check_raises(
    "system dir var missing",
    lambda: one({"NAME": "x"}, "var"),
    "'VARS_DIR' is not defined",
)
_no_runtime = {k: v for k, v in BASE.items() if k != "XDG_RUNTIME_DIR"}
check_raises(
    "runtime kind without any runtime source",
    lambda: one(_no_runtime, "pid", user=True),
    "needs a runtime dir",
)
_no_home = {k: v for k, v in BASE.items() if k != "HOMEDIR"}
_no_home.pop("USERMODE_VARS_DIR")
check_raises(
    "home kind without any home source",
    lambda: one(_no_home, "var", user=True),
    "needs a home",
)

print("")
print("passed: {}  failed: {}".format(passed, failed))
sys.exit(1 if failed else 0)
