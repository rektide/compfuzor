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


def _context_var(variables, name):
    """Resolve a context var with TYPE-prefix precedence.

    Tries C(<TYPE>_<NAME>) first (for example C(MKOSI_PKGS) when C(TYPE=mkosi))
    so each playbook can namespace its package lists without polluting the
    framework-global C(PKGS)/C(PKGSETS) that compfuzor/pkgs.tasks consumes.
    Falls back to the bare C(NAME) when the prefixed var is unset.
    """
    type_name = variables.get("TYPE")
    if isinstance(type_name, str) and type_name:
        prefixed = "{}_{}".format(type_name.upper(), name)
        if prefixed in variables:
            value = variables[prefixed]
            if not (value is None or wrapped_test_undefined(value)):
                return value
    return variables.get(name)


def resolve_pkgs(variables, pkgs=None, pkgset=None, pkgsets=None):
    """Combine direct C(pkgs) with packages resolved from C(pkgset)/C(pkgsets) names.

    Each argument falls back to the matching compfuzor context variable when
    C(None). Resolution order: C(<TYPE>_PKGS)-style prefix wins over the bare
    C(PKGS)/C(PKGSET)/C(PKGSETS), so per-playbook namespacing stays out of the
    framework-global namespace.

    Null-tolerant throughout: an empty list, an absent key, an explicit C(None),
    or a fully empty context all yield C([]). A playbook can therefore leave
    C(MKOSI_PKGS) unset (or set it to C([])) and the result is still the flat
    list of packages pulled from whatever C(MKOSI_PKGSETS) names resolve.
    """
    variables = variables or {}
    direct = _as_list(pkgs if pkgs is not None else _context_var(variables, "PKGS"))
    names = _as_list(pkgset if pkgset is not None else _context_var(variables, "PKGSET"))
    names += _as_list(pkgsets if pkgsets is not None else _context_var(variables, "PKGSETS"))

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
