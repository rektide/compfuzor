"""Render template strings nested inside a value at the current task scope.

Ansible defers template strings nested inside playbook-var containers, and
filter output is never re-templated downstream -- so a declaration like
``ZIM_MODULES: [{env: {VAR: "${V:-{{dir}}"}}]`` reaches consuming filters
with literal ``{{dir}}`` markers unless something forces rendering first.
The ``resolve`` filter cannot do that job reliably on ansible-core >= 2.19:
re-entering the engine from inside a running Jinja filter evaluation trips
the marker/deferral machinery (transient ``UndefinedMarker`` args). Lookups
are the sanctioned re-entrancy point -- ``LookupBase._templar`` is the task
level templar with the full variable scope -- which is why this exists as a
lookup rather than a filter (same pattern as ``vars_dict``).

Ansible lookup exposed:
    ``lookup('template_value', VALUE)`` -- recursively render VALUE's
    template strings now, returning a plain structure.

Per-leaf render errors keep the original leaf (a missing variable must not
crash the walk); ``zim_fragment`` rejects surviving ``{{``/``{%`` markers
loudly so its consumers cannot ship them silently.
"""

from __future__ import annotations

DOCUMENTATION = """
    name: template_value
    author: compfuzor
    short_description: Render template strings nested inside a value now
    description:
      - Re-enters the task templar on each leaf string so template markers nested inside dicts/lists resolve to their final values at the current scope, instead of deferring and later shipping literally.
    options:
      _terms:
        description: value(s) whose nested template strings should render now
        required: true
"""

EXAMPLES = """
- name: render nested declaration values before consuming them
  ansible.builtin.set_fact:
    fragments: "{{ lookup('template_value', zim_modules) | zim_fragment(phase='tools') }}"
"""

RETURN = """
  _raw:
    description:
      - the value(s) with nested template strings rendered at this scope
    type: list
    elements: raw
"""

from ansible.plugins.lookup import LookupBase


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        self.set_options(var_options=variables, direct=kwargs)
        return [_render_value(self._templar, term) for term in terms]


def _render_value(templar, value):
    if isinstance(value, str):
        if "{{" not in value:
            return value
        try:
            return templar.template(value)
        except Exception:
            return value
    if isinstance(value, dict):
        return {k: _render_value(templar, v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        rendered = [_render_value(templar, v) for v in value]
        return tuple(rendered) if isinstance(value, tuple) else rendered
    return value
