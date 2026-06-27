from __future__ import annotations

DOCUMENTATION = """
    name: pkgs
    author: compfuzor
    short_description: Combine PKGS, PKGSET, and PKGSETS into a flat package list
    description:
      - Resolves the standard compfuzor C(PKGS), C(PKGSET), and C(PKGSETS) variables into one flat list of package names.
      - Each entry in C(PKGSET)/C(PKGSETS) is the name of a variable whose own value is a list of packages.
      - Null-tolerant: missing variables, undefined pkgset names, and C(None) entries all collapse to empty.
    options:
      _terms:
        description:
          - Optional list of pkgset names. When provided, overrides C(PKGSETS).
        required: false
      pkgs:
        description:
          - Direct package list prepended to the result. Defaults to the C(PKGS) variable.
        type: list
      pkgset:
        description:
          - Single pkgset name or list of names. Defaults to the C(PKGSET) variable.
      pkgsets:
        description:
          - List of pkgset names. Defaults to the C(PKGSETS) variable.
        type: list
"""

EXAMPLES = """
- name: Resolve compfuzor's standard PKGS/PKGSET/PKGSETS
  ansible.builtin.set_fact:
    all_pkgs: "{{ lookup('pkgs') }}"

- name: Resolve an explicit pkgsets list
  ansible.builtin.set_fact:
    all_pkgs: "{{ lookup('pkgs', pkgsets=['BASE', 'WORKSTATION']) }}"

- name: Positional pkgsets and a direct package on top
  ansible.builtin.set_fact:
    all_pkgs: "{{ lookup('pkgs', ['BASE'], pkgs=['linux-image-amd64']) }}"
"""

RETURN = """
_value:
  description:
    - Flat list of package names.
  type: list
  elements: str
"""

from collections.abc import Sequence

from ansible.plugins.lookup import LookupBase
from ansible.plugins.test.core import wrapped_test_undefined


def _as_list(value):
    if value is None or wrapped_test_undefined(value):
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, Sequence):
        return list(value)
    return [value]


def resolve_pkgs(variables, pkgs=None, pkgset=None, pkgsets=None):
    """Combine direct C(pkgs) with packages resolved from C(pkgset)/C(pkgsets) names.

    Each argument falls back to the matching compfuzor context variable
    (C(PKGS), C(PKGSET), C(PKGSETS)) when C(None).
    """
    variables = variables or {}
    direct = _as_list(pkgs if pkgs is not None else variables.get("PKGS"))
    names = _as_list(pkgset if pkgset is not None else variables.get("PKGSET"))
    names += _as_list(pkgsets if pkgsets is not None else variables.get("PKGSETS"))

    result = list(direct)
    for name in names:
        if not isinstance(name, str) or name == "":
            continue
        result.extend(_as_list(variables.get(name)))
    return result


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        variables = variables or {}
        terms = list(terms or [])
        positional_pkgsets = terms if terms else None
        result = resolve_pkgs(
            variables,
            pkgs=kwargs.get("pkgs"),
            pkgset=kwargs.get("pkgset"),
            pkgsets=positional_pkgsets,
        )
        return [self._templar._engine.template(result)]
