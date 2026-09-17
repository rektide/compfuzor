#!/usr/bin/env python3

import os
import sys

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "library", "filter_plugins"
    )
)

from jinja2 import Environment, StrictUndefined

from template_render import render_templates


def _env():
    # StrictUndefined matches ansible: a missing var raises inside the filter
    # and the value falls through unchanged (default Jinja would render "")."""
    env = Environment(undefined=StrictUndefined)
    env.filters["resolve"] = render_templates
    return env


def test_resolves_whole_string_template():
    env = _env()
    out = env.from_string('{{ "{{ base }}/bin/tool" | resolve }}').render(base="/opt/x")
    assert out == "/opt/x/bin/tool", out


def test_resolves_nested_members_recursively():
    env = _env()
    data = {
        "rows": [
            {"url": "https://example.invalid/{{ v }}/f", "dest": "{{ base }}/bin/f"},
            {"plain": "untouched"},
        ]
    }
    out = env.from_string("{{ data | resolve | tojson }}").render(
        data=data, v="1.2.3", base="/opt/x"
    )
    assert '"https://example.invalid/1.2.3/f"' in out, out
    assert '"/opt/x/bin/f"' in out, out
    assert '"untouched"' in out, out


def test_non_template_strings_pass_through():
    env = _env()
    out = env.from_string('{{ "plain" | resolve }}').render()
    assert out == "plain", out


def test_unresolvable_template_falls_through():
    env = _env()
    out = env.from_string('{{ "{{ missing_var }}/f" | resolve }}').render()
    assert out == "{{ missing_var }}/f", out


def test_non_string_values_pass_through():
    env = _env()
    out = env.from_string("{{ 7 | resolve }}").render()
    assert out == "7", out


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for t in tests:
        t()
    print(f"\nall {len(tests)} tests passed")
