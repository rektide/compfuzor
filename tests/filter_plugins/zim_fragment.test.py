#!/usr/bin/env python3

import os
import sys

from jinja2 import Undefined

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..",
        "..",
        "library",
        "filter_plugins",
    ),
)

from ansible.errors import AnsibleFilterError

from zim_fragment import zim_fragment

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
        print("    actual:   {}".format(repr(actual)))
        print("    expected: {}".format(repr(expected)))


def check_raises(name, fn, fragment):
    global passed, failed
    try:
        fn()
        failed += 1
        print("  FAIL: {} (did not raise)".format(name))
    except AnsibleFilterError as e:
        passed += 1
        print("  PASS: {} ({})".format(name, fragment in str(e)))


def test_string_entry_uses_default_phase():
    print("\nstring entry with default phase:")
    out = zim_fragment("minimal", phase="prompt")
    check(
        "renders under etc/zim with weight 40",
        out,
        [{"name": "zim/40-minimal.conf", "content": "zmodule minimal\n"}],
    )


def test_numeric_phase_name():
    print("\nnumeric phase name:")
    out = zim_fragment([{"source": "fzf", "phase": 55}])
    check(
        "numeric phase used directly, 2-digit padded",
        out[0]["name"],
        "zim/55-fzf.conf",
    )


def test_phase_name_maps_to_number():
    print("\nphase name mapping:")
    cases = {
        "core": 20,
        "prompt": 40,
        "tools": 55,
        "completion": 70,
        "late": 85,
    }
    for name, num in cases.items():
        out = zim_fragment([{"source": "x", "phase": name}])
        check(
            "{} -> {:02d}".format(name, num),
            out[0]["name"],
            "zim/{:02d}-x.conf".format(num),
        )


def test_entry_phase_overrides_default():
    print("\nentry phase overrides default:")
    out = zim_fragment([{"source": "git", "phase": "tools"}], phase="prompt")
    check("uses entry phase 55", out[0]["name"], "zim/55-git.conf")


def test_owner_repo_slug():
    print("\nowner/repo slug:")
    out = zim_fragment([{"source": "zsh-users/zsh-completions", "phase": "completion"}])
    check(
        "takes last path segment",
        out[0]["name"],
        "zim/70-zsh-completions.conf",
    )


def test_url_slug():
    print("\nurl slug:")
    out = zim_fragment(
        [{"source": "https://github.com/joke/zim-mise", "phase": "core"}]
    )
    check("strips scheme + .git", out[0]["name"], "zim/20-zim-mise.conf")


def test_url_with_git_suffix():
    print("\nurl .git suffix:")
    out = zim_fragment(
        [{"source": "https://gitlab.com/Spriithy/basher.git", "phase": "prompt"}]
    )
    check("strips .git", out[0]["name"], "zim/40-basher.conf")


def test_args_string():
    print("\nargs as string:")
    out = zim_fragment(
        [{"source": "zsh-users/zsh-completions", "phase": "completion", "args": "--fpath src"}]
    )
    check(
        "args appended verbatim",
        out[0]["content"],
        "zmodule zsh-users/zsh-completions --fpath src\n",
    )


def test_args_list():
    print("\nargs as list:")
    out = zim_fragment(
        [
            {
                "source": "spaceship-prompt/spaceship-prompt",
                "phase": "prompt",
                "args": ["--name", "spaceship", "--no-submodules"],
            }
        ]
    )
    check(
        "list args space-joined",
        out[0]["content"],
        "zmodule spaceship-prompt/spaceship-prompt --name spaceship --no-submodules\n",
    )


def test_comment_string():
    print("\ncomment string:")
    out = zim_fragment(
        [{"source": "environment", "phase": "core", "comment": "Sets sane options."}]
    )
    check(
        "comment rendered as hash line",
        out[0]["content"],
        "# Sets sane options.\nzmodule environment\n",
    )


def test_comment_multiline_and_list():
    print("\ncomment multiline + list:")
    out = zim_fragment(
        [
            {
                "source": "git-info",
                "phase": "prompt",
                "comment": ["line one", "line two\nline three"],
            }
        ]
    )
    check(
        "each line prefixed with # ",
        out[0]["content"],
        "# line one\n# line two\n# line three\nzmodule git-info\n",
    )


def test_description_in_filename():
    print("\ndescription disambiguator:")
    out = zim_fragment(
        [
            {
                "source": "fzf",
                "phase": "tools",
                "description": "alt",
            }
        ]
    )
    check("description appended", out[0]["name"], "zim/55-fzf-alt.conf")


def test_explicit_name():
    print("\nexplicit name slug:")
    out = zim_fragment([{"source": "x", "phase": "core", "name": "custom"}])
    check("uses explicit name", out[0]["name"], "zim/20-custom.conf")


def test_disabled_routes_to_disabled_dir():
    print("\nenabled false -> disabled dir:")
    out = zim_fragment(
        [{"source": "history-substring-search", "phase": "late", "enabled": False}]
    )
    check(
        "lands in zim-disabled/",
        out[0]["name"],
        "zim-disabled/85-history-substring-search.conf",
    )


def test_single_mapping_input():
    print("\nsingle mapping (not a list):")
    out = zim_fragment({"source": "minimal", "phase": "prompt"})
    check("accepted as one entry", len(out), 1)
    check("correct file", out[0]["name"], "zim/40-minimal.conf")


def test_empty_and_undefined():
    print("\nempty / undefined:")
    check("undefined -> []", zim_fragment(Undefined(name="missing")), [])
    check("none -> []", zim_fragment(None), [])


def test_multiple_entries_order_preserved():
    print("\nmultiple entries:")
    out = zim_fragment(
        [
            {"source": "environment", "phase": "core"},
            {"source": "input", "phase": "core"},
            {"source": "minimal", "phase": "prompt"},
        ]
    )
    check("three fragments", len(out), 3)
    check(
        "names preserve declaration order",
        [r["name"] for r in out],
        [
            "zim/20-environment.conf",
            "zim/20-input.conf",
            "zim/40-minimal.conf",
        ],
    )


def test_out_of_range_phase_rejected():
    print("\nphase range errors:")
    check_raises(
        "100 rejected", lambda: zim_fragment([{"source": "x", "phase": 100}]), "00-99"
    )
    check_raises(
        "negative rejected",
        lambda: zim_fragment([{"source": "x", "phase": -1}]),
        "00-99",
    )


def test_unknown_phase_name_rejected():
    print("\nunknown phase name:")
    check_raises(
        "bogus name rejected",
        lambda: zim_fragment([{"source": "x", "phase": "bogus"}]),
        "phase name",
    )


def test_missing_phase_rejected():
    print("\nmissing phase:")
    check_raises(
        "no phase and no default",
        lambda: zim_fragment([{"source": "x"}]),
        "no phase",
    )


def test_missing_source_rejected():
    print("\nmissing source:")
    check_raises(
        "mapping without source",
        lambda: zim_fragment([{"phase": "core"}]),
        "source",
    )


def test_bool_phase_rejected():
    print("\nbool phase rejected:")
    check_raises(
        "True not 1",
        lambda: zim_fragment([{"source": "x", "phase": True}]),
        "bool",
    )


def test_headroom_numeric():
    print("\nheadroom numeric phases:")
    out = zim_fragment([{"source": "early", "phase": 5}, {"source": "last", "phase": 99}])
    check(
        "pre-core and post-late headroom",
        [r["name"] for r in out],
        ["zim/05-early.conf", "zim/99-last.conf"],
    )


def test_local_file_source_renders_local_module():
    print("\nlocal .zsh source -> local zimfw module:")
    out = zim_fragment(
        [{"source": "watchman-env.zsh", "phase": "tools"}], etc="/etc/opt/watchman-main"
    )
    check("declaration points at rendered module dir", out[0]["name"], "zim/55-watchman-env.conf")
    check(
        "zmodule uses absolute module path",
        out[0]["content"],
        "zmodule /etc/opt/watchman-main/zim-modules/watchman-env\n",
    )
    check("init.zsh record emitted with src", out[1], {"name": "zim-modules/watchman-env/init.zsh", "src": "watchman-env.zsh"})


def test_local_file_explicit_flag():
    print("\nfile: true forces local-file interpretation:")
    out = zim_fragment([{"source": "myscript", "file": True, "phase": "tools"}], etc="/e")
    check("slug kept (no .zsh to strip)", out[0]["name"], "zim/55-myscript.conf")
    check("zmodule path", out[0]["content"], "zmodule /e/zim-modules/myscript\n")


def test_local_file_without_etc_falls_back():
    print("\nlocal file without etc:")
    out = zim_fragment([{"source": "x.zsh", "phase": "core"}])
    check("falls back to bare slug", out[0]["content"], "zmodule x\n")


def test_env_module_renders_generated_script():
    print("\nenv module -> generated init.zsh:")
    out = zim_fragment(
        [{"name": "watchman-env", "phase": "tools", "env": {"WATCHMAN_SOCK": "/path/sock"}}],
        etc="/etc/opt/watchman-main",
    )
    check("declaration points at module dir", out[0]["name"], "zim/55-watchman-env.conf")
    check("zmodule abspath", out[0]["content"], "zmodule /etc/opt/watchman-main/zim-modules/watchman-env\n")
    check("init.zsh carries generated content (not src)", "content" in out[1] and "src" not in out[1], True)
    check("guard line present", 'if [ -z "${WATCHMAN_SOCK:-}" ] || [ -n "${COMPFUZOR_ENV_OVERWRITE:-}" ]; then' in out[1]["content"], True)
    check("export line present", '  export WATCHMAN_SOCK="/path/sock"' in out[1]["content"], True)


def test_env_module_multi_var_order_preserved():
    print("\nenv module multiple vars, declared order:")
    out = zim_fragment(
        [{"name": "m", "phase": "core", "env": {"AAA": "1", "BBB": "2", "CCC": "3"}}],
        etc="/e",
    )
    body = out[1]["content"]
    check("AAA before BBB", body.index("export AAA") < body.index("export BBB"), True)
    check("BBB before CCC", body.index("export BBB") < body.index("export CCC"), True)


def test_env_module_requires_name():
    print("\nenv module without name:")
    check_raises(
        "missing name rejected",
        lambda: zim_fragment([{"phase": "core", "env": {"X": "1"}}]),
        "name",
    )


def test_env_and_source_mutually_exclusive():
    print("\nenv + source rejected:")
    check_raises(
        "both present rejected",
        lambda: zim_fragment([{"source": "x", "phase": "core", "env": {"X": "1"}}]),
        "both",
    )


if __name__ == "__main__":
    test_string_entry_uses_default_phase()
    test_numeric_phase_name()
    test_phase_name_maps_to_number()
    test_entry_phase_overrides_default()
    test_owner_repo_slug()
    test_url_slug()
    test_url_with_git_suffix()
    test_args_string()
    test_args_list()
    test_comment_string()
    test_comment_multiline_and_list()
    test_description_in_filename()
    test_explicit_name()
    test_disabled_routes_to_disabled_dir()
    test_single_mapping_input()
    test_empty_and_undefined()
    test_multiple_entries_order_preserved()
    test_out_of_range_phase_rejected()
    test_unknown_phase_name_rejected()
    test_missing_phase_rejected()
    test_missing_source_rejected()
    test_bool_phase_rejected()
    test_headroom_numeric()
    test_local_file_source_renders_local_module()
    test_local_file_explicit_flag()
    test_local_file_without_etc_falls_back()
    test_env_module_renders_generated_script()
    test_env_module_multi_var_order_preserved()
    test_env_module_requires_name()
    test_env_and_source_mutually_exclusive()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
