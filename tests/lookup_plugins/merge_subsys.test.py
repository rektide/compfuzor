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

from merge_subsys import LookupModule, merge_subsys_value

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


class FakeLazyDict(dict):
    def __getitem__(self, key):
        raise AssertionError("lazy dict rendered")

    def get(self, key, default=None):
        raise AssertionError("lazy dict rendered")

    def items(self):
        raise AssertionError("lazy dict rendered")

    def _non_lazy_copy(self):
        return {key: value for key, value in dict.items(self)}


class FakeTemplateEngine:
    def template(self, value):
        return value


class FakeTemplar:
    def __init__(self):
        self._engine = FakeTemplateEngine()


def test_bins_defaults_merge_current_then_subsystem():
    print("\nmerge_subsys BINS defaults:")
    variables = {
        "BINS": [{"name": "build.sh", "generated": "echo base"}],
        "SUBSYSTEM": {
            "python": {
                "requested": True,
                "contrib": {"BINS": [{"name": "build.sh", "generated": "echo python"}]},
            }
        },
    }
    result = merge_subsys_value(variables, "python", "BINS")
    check(
        "uses BINS defaults",
        result,
        [{"name": "build.sh", "generated": "echo base\necho python"}],
    )


def test_inactive_subsystem_skips_incoming_payload():
    print("\nmerge_subsys active gate:")
    variables = {
        "PKGS": ["base"],
        "SUBSYSTEM": {
            "go": {
                "requested": False,
                "contrib": {"PKGS": ["go"]},
            }
        },
    }
    result = merge_subsys_value(variables, "go", "PKGS")
    check("inactive subsystem ignored", result, ["base"])


def test_fallback_id_and_get_path():
    print("\nmerge_subsys fallback and get:")
    variables = {
        "SUBSYSTEM": {
            "fallback": {
                "requested": True,
                "contrib": {"LINKS": [{"name": "tool"}]},
            }
        },
    }
    result = merge_subsys_value(variables, "", "LINKS", fallback_id="fallback", get="0.name")
    check("uses fallback id and extracts path", result, "tool")


def test_env_current_wins_by_default():
    print("\nmerge_subsys ENV precedence:")
    variables = {
        "ENV": {"PATH": "/current"},
        "SUBSYSTEM": {
            "python": {
                "requested": True,
                "contrib": {"ENV": {"PATH": "/sub", "PYTHON_BIN": "python"}},
            }
        },
    }
    result = merge_subsys_value(variables, "python", "ENV")
    check(
        "current env overrides subsystem env",
        result,
        {"PATH": "/current", "PYTHON_BIN": "python"},
    )


def test_env_incoming_can_win():
    print("\nmerge_subsys ENV incoming wins:")
    variables = {
        "ENV": {"PATH": "/current"},
        "SUBSYSTEM": {
            "python": {
                "requested": True,
                "contrib": {"ENV": {"PATH": "/sub"}},
            }
        },
    }
    result = merge_subsys_value(variables, "python", "ENV", current_wins=False)
    check("subsystem env can override current env", result, {"PATH": "/sub"})


def test_pkgs_append_unique_defaults():
    print("\nmerge_subsys PKGS defaults:")
    variables = {
        "PKGS": ["curl", "git"],
        "SUBSYSTEM": {
            "go": {
                "requested": True,
                "contrib": {"PKGS": ["git", "golang"]},
            }
        },
    }
    result = merge_subsys_value(variables, "go", "PKGS")
    check("dedupes packages preserving order", result, ["curl", "git", "golang"])


def test_current_and_path_overrides():
    print("\nmerge_subsys overrides:")
    variables = {
        "GLOBAL_LINKS": [{"name": "base"}],
        "SUBSYSTEM": {
            "tools": {
                "requested": True,
                "custom": {"links": [{"name": "sub"}]},
            }
        },
    }
    result = merge_subsys_value(
        variables,
        "tools",
        "LINKS",
        current="GLOBAL_LINKS",
        path="custom.links",
    )
    check("reads overridden current and incoming paths", result, [{"name": "base"}, {"name": "sub"}])


def test_raw_copy_boundary_for_variables():
    print("\nmerge_subsys raw-copy boundary:")
    variables = FakeLazyDict(
        {
            "BINS": [],
            "SUBSYSTEM": FakeLazyDict(
                {
                    "python": {
                        "requested": True,
                        "contrib": {"BINS": [{"name": "build.sh"}]},
                    }
                }
            ),
        }
    )
    result = merge_subsys_value(variables, "python", "BINS")
    check("uses _non_lazy_copy for variables", result, [{"name": "build.sh"}])


def test_lookup_run_returns_templated_result_list():
    print("\nmerge_subsys lookup run:")
    lookup = LookupModule()
    lookup._templar = FakeTemplar()
    variables = {
        "ENV": {"PATH": "/current"},
        "SUBSYSTEM": {
            "python": {
                "requested": True,
                "contrib": {"ENV": {"PYTHON_BIN": "python"}},
            }
        },
    }
    result = lookup.run([], variables=variables, id="python", contrib="ENV")
    check("returns one lookup result", result, [{"PATH": "/current", "PYTHON_BIN": "python"}])


def test_etc_dirs_append_defaults():
    print("\nmerge_subsys ETC_DIRS defaults:")
    variables = {
        "ETC_DIRS": ["/etc/base"],
        "SUBSYSTEM": {
            "config": {
                "requested": True,
                "contrib": {"ETC_DIRS": ["myconf", "myconf-disabled"]},
            }
        },
    }
    result = merge_subsys_value(variables, "config", "ETC_DIRS")
    check("appends ETC_DIRS after current", result, ["/etc/base", "myconf", "myconf-disabled"])


def test_requested_from_variable():
    print("\nmerge_subsys requested from variable:")
    variables = {
        "RUST": True,
        "BINS": [],
        "SUBSYSTEM": {
            "rust": {
                "contrib": {"BINS": [{"name": "build.sh"}, {"name": "install.sh"}]},
            }
        },
    }
    result = merge_subsys_value(variables, "rust", "BINS")
    check("resolves active from variable when no requested field", result, [{"name": "build.sh"}, {"name": "install.sh"}])


def test_explicit_active_path_still_works():
    print("\nmerge_subsys explicit active_path:")
    variables = {
        "BINS": [],
        "SUBSYSTEM": {
            "custom": {
                "my_active_flag": True,
                "contrib": {"BINS": [{"name": "run.sh"}]},
            }
        },
    }
    result = merge_subsys_value(variables, "custom", "BINS", active_path="my_active_flag")
    check("reads custom active_path from record", result, [{"name": "run.sh"}])


def test_lookup_run_rejects_positional_terms():
    print("\nmerge_subsys lookup positional terms:")
    lookup = LookupModule()
    lookup._templar = FakeTemplar()
    try:
        lookup.run(["python"], variables={}, contrib="BINS")
        check("should have raised", False, True)
    except AnsibleError as e:
        check("rejects positional terms", "does not support positional terms" in str(e), True)


if __name__ == "__main__":
    test_bins_defaults_merge_current_then_subsystem()
    test_inactive_subsystem_skips_incoming_payload()
    test_fallback_id_and_get_path()
    test_env_current_wins_by_default()
    test_env_incoming_can_win()
    test_pkgs_append_unique_defaults()
    test_current_and_path_overrides()
    test_raw_copy_boundary_for_variables()
    test_etc_dirs_append_defaults()
    test_requested_from_variable()
    test_explicit_active_path_still_works()
    test_lookup_run_returns_templated_result_list()
    test_lookup_run_rejects_positional_terms()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
