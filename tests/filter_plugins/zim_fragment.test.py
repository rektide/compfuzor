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
        [{"name": "zim/zimrc/active/40-minimal.conf", "content": "zmodule minimal\n"}],
    )


def test_numeric_phase_name():
    print("\nnumeric phase name:")
    out = zim_fragment([{"source": "fzf", "phase": 55}])
    check(
        "numeric phase used directly, 2-digit padded",
        out[0]["name"],
        "zim/zimrc/active/55-fzf.conf",
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
            "zim/zimrc/active/{:02d}-x.conf".format(num),
        )


def test_entry_phase_overrides_default():
    print("\nentry phase overrides default:")
    out = zim_fragment([{"source": "git", "phase": "tools"}], phase="prompt")
    check("uses entry phase 55", out[0]["name"], "zim/zimrc/active/55-git.conf")


def test_channel_routes_fragment():
    print("\nchannel routing:")
    out = zim_fragment(
        [{"source": "rektide/zim-mise", "phase": "core", "channel": "zimenv"}]
    )
    check(
        "explicit channel selects its active tree",
        out[0]["name"],
        "zim/zimenv/active/20-zim-mise.conf",
    )
    check_raises(
        "unsupported channel rejected",
        lambda: zim_fragment(
            [{"source": "x", "phase": "core", "channel": "other"}]
        ),
        "channel",
    )


def test_owner_repo_slug():
    print("\nowner/repo slug:")
    out = zim_fragment([{"source": "zsh-users/zsh-completions", "phase": "completion"}])
    check(
        "takes last path segment",
        out[0]["name"],
        "zim/zimrc/active/70-zsh-completions.conf",
    )


def test_url_slug():
    print("\nurl slug:")
    out = zim_fragment(
        [{"source": "https://github.com/joke/zim-mise", "phase": "core"}]
    )
    check("strips scheme + .git", out[0]["name"], "zim/zimrc/active/20-zim-mise.conf")


def test_url_with_git_suffix():
    print("\nurl .git suffix:")
    out = zim_fragment(
        [{"source": "https://gitlab.com/Spriithy/basher.git", "phase": "prompt"}]
    )
    check("strips .git", out[0]["name"], "zim/zimrc/active/40-basher.conf")


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
    check("description appended", out[0]["name"], "zim/zimrc/active/55-fzf-alt.conf")


def test_explicit_name():
    print("\nexplicit name slug:")
    out = zim_fragment([{"source": "x", "phase": "core", "name": "custom"}])
    check("uses explicit name", out[0]["name"], "zim/zimrc/active/20-custom.conf")


def test_disabled_routes_to_disabled_dir():
    print("\nenabled false -> disabled dir:")
    out = zim_fragment(
        [{"source": "history-substring-search", "phase": "late", "enabled": False}]
    )
    check(
        "lands in the channel disabled tree",
        out[0]["name"],
        "zim/zimrc/disabled/85-history-substring-search.conf",
    )


def test_single_mapping_input():
    print("\nsingle mapping (not a list):")
    out = zim_fragment({"source": "minimal", "phase": "prompt"})
    check("accepted as one entry", len(out), 1)
    check("correct file", out[0]["name"], "zim/zimrc/active/40-minimal.conf")


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
            "zim/zimrc/active/20-environment.conf",
            "zim/zimrc/active/20-input.conf",
            "zim/zimrc/active/40-minimal.conf",
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
        ["zim/zimrc/active/05-early.conf", "zim/zimrc/active/99-last.conf"],
    )


def test_local_file_source_renders_local_module():
    print("\nlocal .zsh source -> local zimfw module:")
    out = zim_fragment(
        [{"source": "watchman-env.zsh", "phase": "tools"}], etc="/etc/opt/watchman-main"
    )
    check("declaration points at rendered module dir", out[0]["name"], "zim/zimrc/active/55-watchman-env.conf")
    check(
        "zmodule uses absolute module path",
        out[0]["content"],
        "zmodule /etc/opt/watchman-main/zim-modules/watchman-env\n",
    )
    check("init.zsh record emitted with src", out[1], {"name": "zim-modules/watchman-env/init.zsh", "src": "watchman-env.zsh"})


def test_local_file_explicit_flag():
    print("\nfile: true forces local-file interpretation:")
    out = zim_fragment([{"source": "myscript", "file": True, "phase": "tools"}], etc="/e")
    check("slug kept (no .zsh to strip)", out[0]["name"], "zim/zimrc/active/55-myscript.conf")
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
    check("declaration points at module dir", out[0]["name"], "zim/zimrc/active/55-watchman-env.conf")
    check("zmodule abspath", out[0]["content"], "zmodule /etc/opt/watchman-main/zim-modules/watchman-env\n")
    check("init.zsh carries generated content (not src)", "content" in out[1] and "src" not in out[1], True)
    check("overwrite helper defined", "_compfuzor_env_overwrite()" in out[1]["content"], True)
    check("all-tokens guard present", "1|TRUE|YES|Y|'*'" in out[1]["content"], True)
    check("comma-split + glob match present", 'case "${(U)1}" in $~p) return 0' in out[1]["content"], True)
    check("setter checks existing value", '[ -n "${(P)name:-}" ] && ! _compfuzor_env_overwrite "$name" && return 0' in out[1]["content"], True)
    check("setter call present", '_compfuzor_env_set WATCHMAN_SOCK "/path/sock"' in out[1]["content"], True)


def test_env_module_multi_var_order_preserved():
    print("\nenv module multiple vars, declared order:")
    out = zim_fragment(
        [{"name": "m", "phase": "core", "env": {"AAA": "1", "BBB": "2", "CCC": "3"}}],
        etc="/e",
    )
    body = out[1]["content"]
    check("AAA before BBB", body.index("_compfuzor_env_set AAA") < body.index("_compfuzor_env_set BBB"), True)
    check("BBB before CCC", body.index("_compfuzor_env_set BBB") < body.index("_compfuzor_env_set CCC"), True)


def test_array_module_renders_explicit_array_references():
    print("\narray module -> generated init.zsh:")
    out = zim_fragment(
        [
            {
                "name": "shell-arrays",
                "phase": "core",
                "arrays": {
                    "fpath": ["/one function", "/two"],
                    "path": ["$HOME/.local/bin", "/usr/bin"],
                },
            }
        ],
        etc="/e",
    )
    body = out[1]["content"]
    check("array module declaration", out[0]["name"], "zim/zimrc/active/20-shell-arrays.conf")
    check("explicit temporary array", 'typeset -a _compfuzor_array_values_0=("/one function" "/two")' in body, True)
    check("setter receives array name", "_compfuzor_array_set fpath _compfuzor_array_values_0" in body, True)
    check("path is supported", '_compfuzor_array_set path _compfuzor_array_values_1' in body, True)
    check("setter uses indirect array expansion", 'set -A "$name" "${(@P)values_name}"' in body, True)


def test_array_module_validation():
    print("\narray module validation:")
    check_raises(
        "array value must be list",
        lambda: zim_fragment(
            [{"name": "m", "phase": "tools", "arrays": {"path": "/bin"}}]
        ),
        "must be a list",
    )
    check_raises(
        "array name must be identifier",
        lambda: zim_fragment(
            [{"name": "m", "phase": "tools", "arrays": {"bad-name": ["x"]}}]
        ),
        "valid Zsh identifiers",
    )
    check_raises(
        "array elements cannot nest",
        lambda: zim_fragment(
            [{"name": "m", "phase": "tools", "arrays": {"path": [["x"]]}}]
        ),
        "must be scalars",
    )
    check_raises(
        "array module requires name",
        lambda: zim_fragment([{"phase": "tools", "arrays": {"path": ["/bin"]}}]),
        "requires 'name'",
    )


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


def test_aliases_module_renders_generated_script():

    print("\naliases module:")
    out = zim_fragment(
        [{"name": "handy", "phase": "tools", "aliases": {"gs": "git status"}}],
        etc="/x",
    )
    check(
        "renders alias lines",
        out[1]["content"],
        "# Auto-generated by compfuzor zim (aliases module).\nalias gs='git status'\n",
    )
    check(
        "init.zsh record name",
        out[1]["name"],
        "zim-modules/handy/init.zsh",
    )


def test_aliases_quoting_escapes_single_quotes():

    print("\naliases quoting:")
    out = zim_fragment(
        [{"name": "q", "phase": "tools", "aliases": {"yolo": "echo it's"}}], etc="/x"
    )
    check(
        "embedded quote escaped",
        out[1]["content"],
        "# Auto-generated by compfuzor zim (aliases module).\nalias yolo='echo it'\\''s'\n",
    )


def test_functions_module_renders_generated_script():

    print("\nfunctions module:")
    out = zim_fragment(
        [
            {
                "name": "push",
                "phase": "tools",
                "functions": {"pushIt": "jj push -b main"},
            }
        ],
        etc="/x",
    )
    check(
        "renders function definition",
        out[1]["content"],
        "# Auto-generated by compfuzor zim (functions module).\npushIt() {\n  jj push -b main\n}\n",
    )


def test_completions_pure_module():

    print("\ncompletions-only module:")
    out = zim_fragment(
        [{"name": "comps", "phase": "completion", "completions": ["_mise"]}], etc="/x"
    )
    check(
        "init.zsh is fpath line",
        out[1],
        {
            "name": "zim-modules/comps/init.zsh",
            "content": "fpath=(${0:h}/functions $fpath)\n",
        },
    )
    check(
        "completion src record",
        out[2],
        {"name": "zim-modules/comps/functions/_mise", "src": "_mise"},
    )


def test_completions_ride_along_with_env():

    print("\nenv module + completions:")
    out = zim_fragment(
        [
            {
                "name": "both",
                "phase": "tools",
                "env": {"X": "1"},
                "completions": ["_x", "_y"],
            }
        ],
        etc="/x",
    )
    check(
        "fpath line leads the generated init.zsh",
        out[1]["content"].splitlines()[0],
        "fpath=(${0:h}/functions $fpath)",
    )
    check(
        "completion src records emitted",
        [r["name"] for r in out[2:]],
        ["zim-modules/both/functions/_x", "zim-modules/both/functions/_y"],
    )


def test_completions_with_file_module_wrap_body():

    print("\nfile module + completions:")
    out = zim_fragment(
        [
            {
                "name": "wrapped",
                "phase": "tools",
                "source": "wrapped.zsh",
                "completions": ["_wrapped"],
            }
        ],
        etc="/x",
    )
    check(
        "generated init sources body.zsh",
        out[1]["content"],
        "fpath=(${0:h}/functions $fpath)\nsource ${0:h}/body.zsh\n",
    )
    check(
        "body.zsh src record",
        out[2],
        {"name": "zim-modules/wrapped/body.zsh", "src": "wrapped.zsh"},
    )
    check(
        "completion src record",
        out[3],
        {"name": "zim-modules/wrapped/functions/_wrapped", "src": "_wrapped"},
    )


def test_file_module_without_completions_unchanged():

    print("\nfile module without completions stays direct:")
    out = zim_fragment([{"source": "plain.zsh", "phase": "tools"}], etc="/x")
    check(
        "init.zsh src record (no wrapper)",
        out[1],
        {"name": "zim-modules/plain/init.zsh", "src": "plain.zsh"},
    )


def test_body_kinds_mutually_exclusive():

    print("\nbody kind exclusivity:")
    check_raises(
        "aliases + functions rejected",
        lambda: zim_fragment(
            [{"name": "m", "phase": "tools", "aliases": {"a": "b"}, "functions": {"f": "g"}}]
        ),
        "only one of",
    )
    check_raises(
        "env + aliases rejected",
        lambda: zim_fragment(
            [{"name": "m", "phase": "tools", "env": {"X": "1"}, "aliases": {"a": "b"}}]
        ),
        "only one of",
    )
    check_raises(
        "env + arrays rejected",
        lambda: zim_fragment(
            [
                {
                    "name": "m",
                    "phase": "tools",
                    "env": {"X": "1"},
                    "arrays": {"path": ["/bin"]},
                }
            ]
        ),
        "only one of",
    )


def test_aliases_and_functions_require_name():

    print("\naliases/functions name requirement:")
    check_raises(
        "aliases without name rejected",
        lambda: zim_fragment([{"phase": "tools", "aliases": {"a": "b"}}]),
        "requires 'name'",
    )
    check_raises(
        "functions without name rejected",
        lambda: zim_fragment([{"phase": "tools", "functions": {"f": "g"}}]),
        "requires 'name'",
    )


def test_completions_validation():

    print("\ncompletions validation:")
    check_raises(
        "empty completions rejected",
        lambda: zim_fragment(
            [{"name": "m", "phase": "tools", "completions": []}]
        ),
        "empty",
    )
    check_raises(
        "path in completion name rejected",
        lambda: zim_fragment(
            [{"name": "m", "phase": "tools", "completions": ["a/b"]}]
        ),
        "plain filenames",
    )


if __name__ == "__main__":
    test_string_entry_uses_default_phase()
    test_numeric_phase_name()
    test_phase_name_maps_to_number()
    test_entry_phase_overrides_default()
    test_channel_routes_fragment()
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
    test_array_module_renders_explicit_array_references()
    test_array_module_validation()
    test_env_module_requires_name()
    test_env_and_source_mutually_exclusive()
    test_aliases_module_renders_generated_script()
    test_aliases_quoting_escapes_single_quotes()
    test_functions_module_renders_generated_script()
    test_completions_pure_module()
    test_completions_ride_along_with_env()
    test_completions_with_file_module_wrap_body()
    test_file_module_without_completions_unchanged()
    test_body_kinds_mutually_exclusive()
    test_aliases_and_functions_require_name()
    test_completions_validation()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
