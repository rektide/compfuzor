from __future__ import annotations

DOCUMENTATION = """
    name: vars_list
    author: compfuzor
    short_description: Resolve a list of variable names into a list of values
    description:
      - Works like C(ansible.builtin.vars), but accepts a list of variable names and returns a resolved list.
    options:
      _terms:
        description:
          - Variable names to resolve.
          - Each term may be a string variable name or a list of string variable names.
        required: true
      default:
        description:
          - Value used when a variable is undefined.
          - If omitted, an undefined variable error is returned for missing variables.
"""

EXAMPLES = """
- name: Resolve a list variable containing variable names
  ansible.builtin.set_fact:
    resolved_values: "{{ lookup('vars_list', my_var_names) }}"

- name: Resolve explicit variable names
  ansible.builtin.set_fact:
    resolved_values: "{{ lookup('vars_list', ['FOO', 'BAR']) }}"

- name: Resolve with default for missing variable names
  ansible.builtin.set_fact:
    resolved_values: "{{ lookup('vars_list', ['FOO', 'MISSING'], default='') }}"
"""

RETURN = """
_value:
  description:
    - List of resolved variable values.
  type: list
  elements: raw
"""

from collections.abc import Sequence

from ansible.errors import AnsibleTypeError
from ansible.module_utils.datatag import native_type_name
from ansible.plugins.lookup import LookupBase
from ansible._internal._templating import _jinja_bits


def _iter_var_names(terms):
    for term in terms:
        if isinstance(term, Sequence) and not isinstance(term, str):
            for name in term:
                yield name
        else:
            yield term


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        variables = variables or {}
        self.set_options(var_options=variables, direct=kwargs)

        default = self.get_option("default")
        resolved = []

        for term in _iter_var_names(terms):
            if not isinstance(term, str):
                raise AnsibleTypeError(
                    f"Variable name must be {native_type_name(str)!r} not {native_type_name(term)!r}.",
                    obj=term,
                )

            try:
                value = variables[term]
            except KeyError:
                if default is None:
                    value = _jinja_bits._undef(f"No variable named {term!r} was found.")
                else:
                    value = default

            resolved.append(value)

        return [self._templar._engine.template(resolved)]
