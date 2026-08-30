#!/usr/bin/env python3

"""`comments` support in the generated systemd unit template.

files/systemd.unit accepts a `comments` key in any per-section dict
(SYSTEMD_UNITS, SYSTEMD_SERVICES, SYSTEMD_SOCKETS, SYSTEMD_INSTALLS, and
every other SYSTEMD_<SECTION>S var, including per-root sections under
SYSTEMD_ROOTS and SYSTEMD_DROPIN(S) specs). The value -- a string or a
list of strings -- renders as `# ...` lines directly above the [Section]
header and must never leak into the directive loop.

Three layers:
  1. hermetic jinja2 renders of files/systemd.unit (exact output)
  2. ansible's combine filter: `comments` survives the `_merged_sections`
     recursive merge chain from tasks/compfuzor/vars_systemd_unit.tasks
  3. end-to-end ansible-playbook through the real task file: top-level
     vars, SYSTEMD_ROOTS per-root sections, and SYSTEMD_DROPINS drop-ins
     (the playbook must live at the repo root for the
     `lookup('template', 'files/systemd.unit')` search path).
"""

import json
import subprocess
import tempfile
from pathlib import Path

import jinja2


ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "files/systemd.unit"
TYPE_CONFIG = {
    "service": {"sections": ["Unit", "Service", "Install"]},
    "socket": {"sections": ["Unit", "Socket", "Install"]},
}


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


# --- layer 1: hermetic jinja2 renders --------------------------------------


def render(unit_vars, unit_type="service", global_vars=None):
    """Render the unit template like vars_systemd_unit.tasks does.

    UNIT_VARS holds the merged per-section dicts; section vars missing
    from it fall back to lookup('vars', ...) the same way the template's
    last loop does.
    """
    globals_store = dict(global_vars or {})

    def fake_lookup(plugin, *args, **kwargs):
        if plugin == "vars":
            return globals_store.get(args[0], kwargs.get("default"))
        return kwargs.get("default")

    environment = jinja2.Environment(undefined=jinja2.Undefined)
    environment.globals["lookup"] = fake_lookup
    return environment.from_string(TEMPLATE.read_text(encoding="utf-8")).render(
        SYSTEMD_TYPE_CONFIG=TYPE_CONFIG,
        UNIT_TYPE=unit_type,
        UNIT_VARS=unit_vars,
        vars={},
    )


def services(**fields):
    return {"SYSTEMD_SERVICES": fields}


def test_string_comments_render_above_header():
    output = render(
        {
            "SYSTEMD_UNITS": {"Description": "demo"},
            "SYSTEMD_SERVICES": {
                "comments": (
                    "Type=notify pairs with the daemon's sd_notify READY;\n"
                    "the socket unit owns the bind, so we never unlink."
                ),
                "Type": "notify",
                "ExecStart": "/usr/bin/foo",
            },
        }
    )
    check(
        "string comments render above the section header",
        output,
        "[Unit]\n"
        "Description=demo\n"
        "# Type=notify pairs with the daemon's sd_notify READY;\n"
        "# the socket unit owns the bind, so we never unlink.\n"
        "[Service]\n"
        "Type=notify\n"
        "ExecStart=/usr/bin/foo\n",
    )


def test_block_scalar_trailing_newline_is_not_a_comment_line():
    # A YAML `|` block scalar clips to one trailing newline; that line is
    # syntax, not content, so it must not become a stray bare `#`.
    output = render(services(comments="a\nb\n", Type="simple"))
    check(
        "trailing blank line dropped",
        output,
        "# a\n# b\n[Service]\nType=simple\n",
    )


def test_list_comments_with_multiline_entries_and_rstrip():
    output = render(services(comments=["first line   ", "", "second"], Type="exec"))
    check(
        "list comments, trailing whitespace stripped, interior blank is bare #",
        output,
        "# first line\n#\n# second\n[Service]\nType=exec\n",
    )


def test_empty_and_falsy_comment_values_render_nothing():
    for value in ("", [], False, None, " \n \n", "\n"):
        output = render(services(comments=value, Type="simple"))
        check(
            f"empty-ish comments {value!r} render nothing",
            output,
            "[Service]\nType=simple\n",
        )


def test_comments_only_section_still_renders_header():
    # Design decision: a section whose only content is comments renders
    # the comments followed by the bare header, keeping the comment
    # anchored to its section (free-floating comments would visually
    # attach to the wrong section).
    check(
        "comments-only section renders comments then bare header",
        render({"SYSTEMD_SERVICES": {"comments": "nothing to configure"}}),
        "# nothing to configure\n[Service]\n",
    )
    check(
        "empty section with no comments renders nothing (unchanged)",
        render({"SYSTEMD_SERVICES": {}}),
        "",
    )


def test_comments_never_leak_into_the_directive_loop():
    output = render(
        services(
            comments="c",
            ExecStart=["/bin/a", "/bin/b"],
            Drop=False,
            Environment="A=1\nB=2",
        )
    )
    check(
        "comments skipped in field loop; list, false, and multiline "
        "field behavior unchanged",
        output,
        "# c\n"
        "[Service]\n"
        "ExecStart=/bin/a\n"
        "ExecStart=/bin/b\n"
        "Environment=A=1 \\\n\tB=2\n",
    )
    check("no comments= directive ever emitted", "comments=" in output, False)


def test_comments_on_every_section_of_every_rendered_type():
    output = render(
        {
            "SYSTEMD_UNITS": {"Description": "s", "comments": "top"},
            "SYSTEMD_SOCKETS": {
                "ListenStream": "%t/x.sock",
                "comments": ["own the bind"],
            },
            "SYSTEMD_INSTALLS": {"WantedBy": "sockets.target"},
        },
        unit_type="socket",
    )
    check(
        "comments above [Unit], [Socket] headers alike",
        output,
        "# top\n"
        "[Unit]\n"
        "Description=s\n"
        "# own the bind\n"
        "[Socket]\n"
        "ListenStream=%t/x.sock\n"
        "[Install]\n"
        "WantedBy=sockets.target\n",
    )


def test_section_var_lookup_fallback_still_works():
    output = render(
        {"SYSTEMD_SERVICES": {"comments": "x", "Type": "notify"}},
        global_vars={"SYSTEMD_INSTALLS": {"WantedBy": "multi-user.target"}},
    )
    check(
        "sections missing from UNIT_VARS fall back to global vars",
        output,
        "# x\n[Service]\nType=notify\n[Install]\nWantedBy=multi-user.target\n",
    )


def test_falsy_section_data_skips_and_truthy_garbage_fails_loud():
    check("falsy section data renders nothing (unchanged)", render({"SYSTEMD_SERVICES": False}), "")
    try:
        render({"SYSTEMD_SERVICES": "garbage"})
    except Exception:
        print("ok: truthy non-mapping section data still fails loudly")
    else:
        raise AssertionError("truthy non-mapping section data should fail loudly")


# --- layer 2: the _merged_sections combine chain ----------------------------


def test_comments_survive_the_merged_sections_combine_chain():
    # vars_systemd_unit.tasks builds each section as
    #   defaults | combine(user_vals, recursive=True)
    # where user_vals = global_vals | combine(root_vals, recursive=True).
    # A plain string/list `comments` value is a scalar to combine, so it
    # passes through (and the most specific scope wins, like any field).
    from ansible.plugins.filter.core import combine

    defaults = {"Type": "simple", "Restart": "on-failure"}
    global_vals = {"Type": "notify", "comments": "global note"}
    root_vals = {"comments": ["root", "note"], "ExecStart": "/usr/bin/foo"}

    user_vals = combine(global_vals, root_vals, recursive=True)
    merged = combine(defaults, user_vals, recursive=True)
    check(
        "most specific scope wins for comments",
        merged["comments"],
        ["root", "note"],
    )
    check("fields still merge", merged["Type"], "notify")
    check("defaults still apply", merged["Restart"], "on-failure")

    no_root = combine(defaults, combine(global_vals, {}, recursive=True), recursive=True)
    check("global comments survive without a root override", no_root["comments"], "global note")


# --- layer 3: end-to-end ansible-playbook ----------------------------------


def run_playbook(playbook: str, workdir: Path) -> list[dict]:
    """Run a playbook against the real task file, return ETC_FILES.

    The playbook is written to the repo root (dot-prefixed, gitignored)
    because `lookup('template', 'files/systemd.unit')` resolves relative
    to the playbook directory.
    """
    playbook_path = ROOT / ".test-agent-systemd-unit-comments-e2e.pb"
    output_path = workdir / "etc_files.json"
    playbook_path.write_text(
        playbook.replace("@ROOT@", str(ROOT)).replace("@OUTPUT@", str(output_path)),
        encoding="utf-8",
    )
    try:
        result = subprocess.run(
            [
                "ansible-playbook",
                "-i",
                "localhost,",
                "-c",
                "local",
                str(playbook_path),
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"playbook failed:\n{result.stdout}\n{result.stderr}"
            )
    finally:
        playbook_path.unlink(missing_ok=True)
    return json.loads(output_path.read_text(encoding="utf-8"))


PLAYBOOK_SECTIONS = """
---
- hosts: all
  gather_facts: false
  vars_files:
    - @ROOT@/vars/systemd.yaml
  vars:
    NAME: cmt
    SYSTEMD_UNITS:
      comments: |
        top-level Unit comment
      Description: demo
    SYSTEMD_SERVICES:
      comments: |
        Type=notify pairs with the daemon's sd_notify READY;
        the socket unit owns the bind, so we never unlink.
      Type: notify
      ExecStart: /usr/bin/foo
    SYSTEMD_ROOTS: [cmtSocket]
    cmtSocket:
      SYSTEMD_SOCKET: cmt
      SYSTEMD_SOCKETS:
        comments:
          - "%t == $XDG_RUNTIME_DIR"
          - the socket unit owns the bind
        ListenStream: "%t/cmt.sock"
      SYSTEMD_INSTALLS:
        comments: sockets.target pulls the socket up early
        WantedBy: sockets.target
  tasks:
    - import_tasks: @ROOT@/tasks/compfuzor/vars_systemd_unit.tasks
    - copy:
        dest: "@OUTPUT@"
        content: "{{ ETC_FILES | to_json }}"
"""


def test_end_to_end_top_level_and_roots_rendering():
    with tempfile.TemporaryDirectory(prefix="compfuzor-systemd-comments-") as tmp:
        etc_files = run_playbook(PLAYBOOK_SECTIONS, Path(tmp))
    by_name = {entry["name"]: entry["content"] for entry in etc_files}
    check(
        "top-level unit comments merge with section defaults end-to-end",
        by_name["cmt.service"],
        "# top-level Unit comment\n"
        "[Unit]\n"
        "Description=demo\n"
        "DefaultDependencies=True\n"
        "# Type=notify pairs with the daemon's sd_notify READY;\n"
        "# the socket unit owns the bind, so we never unlink.\n"
        "[Service]\n"
        "Type=notify\n"
        "Restart=on-failure\n"
        "RestartSec=5\n"
        "ExecStart=/usr/bin/foo\n"
        "[Install]\n"
        "WantedBy=multi-user.target\n",
    )
    check(
        "SYSTEMD_ROOTS per-root section comments render",
        by_name["cmt.socket"],
        "# top-level Unit comment\n"  # global SYSTEMD_UNITS merges into roots too
        "[Unit]\n"
        "Description=demo\n"
        "DefaultDependencies=True\n"
        "# %t == $XDG_RUNTIME_DIR\n"
        "# the socket unit owns the bind\n"
        "[Socket]\n"
        "ListenStream=%t/cmt.sock\n"
        "# sockets.target pulls the socket up early\n"
        "[Install]\n"
        "WantedBy=sockets.target\n",
    )


PLAYBOOK_DROPIN = """
---
- hosts: all
  gather_facts: false
  vars_files:
    - @ROOT@/vars/systemd.yaml
  vars:
    NAME: cmt
    SYSTEMD_DROPINS:
      - name: hardening
        target: cmt.service
        SYSTEMD_SERVICES:
          comments: |
            defense in depth: lock the unit down further
          NoNewPrivileges: true
  tasks:
    - import_tasks: @ROOT@/tasks/compfuzor/vars_systemd_unit.tasks
    - copy:
        dest: "@OUTPUT@"
        content: "{{ ETC_FILES | to_json }}"
"""


def test_end_to_end_dropin_comments_render():
    # SYSTEMD_DROPIN(S) render through the same template (no defaults
    # merge in that path), so comments work there for free.
    with tempfile.TemporaryDirectory(prefix="compfuzor-systemd-comments-") as tmp:
        etc_files = run_playbook(PLAYBOOK_DROPIN, Path(tmp))
    by_name = {entry["name"]: entry["content"] for entry in etc_files}
    check(
        "drop-in section comments render above the header",
        by_name["cmt.service.d/hardening.conf"],
        "# defense in depth: lock the unit down further\n"
        "[Service]\n"
        "NoNewPrivileges=True\n",
    )


if __name__ == "__main__":
    test_string_comments_render_above_header()
    test_block_scalar_trailing_newline_is_not_a_comment_line()
    test_list_comments_with_multiline_entries_and_rstrip()
    test_empty_and_falsy_comment_values_render_nothing()
    test_comments_only_section_still_renders_header()
    test_comments_never_leak_into_the_directive_loop()
    test_comments_on_every_section_of_every_rendered_type()
    test_section_var_lookup_fallback_still_works()
    test_falsy_section_data_skips_and_truthy_garbage_fails_loud()
    test_comments_survive_the_merged_sections_combine_chain()
    test_end_to_end_top_level_and_roots_rendering()
    test_end_to_end_dropin_comments_render()
