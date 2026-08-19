from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = """
    name: fsh
    author: compfuzor
    short_description: file-system-hierarchy aware directory lookup
    description:
      - Resolves a compfuzor directory kind (var, etc, srv, log, ...) to the
        base directory appropriate for the current mode.
      - Plain mode returns the deploy-mode base (VARS_DIR and friends), which
        under a USERMODE playbook is already the user hierarchy -- "picks
        intelligently" means the lookup follows whatever flip already
        happened.
      - C(user=True) selects the user hierarchy explicitly (the
        USERMODE_*_DIR family, resolved for the deploying user).
      - A truthy top-level C(USER_FSH) variable flips the source to the
        specifier family -- C(%h)/C(%t) paths that systemd expands at
        unit-load time -- making user-scope units portable across activating
        users (global deploy, per-user activation). The systemd unit
        generation loop sets the reserved C(_fsh_user) variable for
        user-scope iterations of C(SYSTEMD_INSTALL=separate) renders, so a
        single SYSTEMD_SERVICES block renders system paths for the system
        unit and specifier paths for the user unit.
      - C(name=True) appends C(NAME); in plain mode a frozen hierarchy
        variable (VAR, ETC, SRV, ...) is preferred when present, matching
        the vars_hierarchy set_fact freeze.
      - The specifier table can be overridden per-kind with a
        C(USER_FSH_DIRS) mapping variable (or by making C(USER_FSH) itself a
        mapping).
      - Kinds without a user-relative specifier (only I(bins), where a global
        deploy keeps its managed bins global) fall back to the system dir
        even under the flip.
    options:
      user:
        description: Select the user hierarchy (USERMODE_*_DIR family).
        type: boolean
        default: false
      name:
        description: Append NAME; prefer the frozen hierarchy variable in plain mode.
        type: boolean
        default: false
"""

EXAMPLES = """
- name: Deploy-mode base dir (follows USERMODE flip)
  debug:
    msg: "{{ lookup('fsh', 'var') }}"

- name: Per-user state path, resolved for the deploying user
  debug:
    msg: "{{ lookup('fsh', 'var', user=True, name=True) }}"

- name: Per-user state path as a systemd specifier (USER_FSH flip)
  debug:
    msg: "{{ lookup('fsh', 'var', user=True, name=True) }}"
  # renders %h/.local/var/lib/watchman-main when USER_FSH is set
"""

RETURN = """
_raw:
  description:
    - Resolved directory path(s), one per term. Values are templated; systemd
      specifiers (%h, %t) pass through untouched.
  type: list
  elements: string
"""

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase

# kind -> sources.
#   sys:    deploy-mode base variable (VARS_DIR and friends)
#   user:   USERMODE_* resolved-user variable
#   spec:   USER_FSH specifier default (systemd expands %h/%t at unit load)
#   frozen: implicit hierarchy var from vars_hierarchy.tasks (VAR, ETC, ...)
#   user_runtime: user resolved dir comes from XDG_RUNTIME_DIR, not USERMODE_*
FSH_KINDS = {
    'opt': {'sys': 'OPTS_DIR', 'user': 'USERMODE_OPTS_DIR', 'spec': '%h/.local/opt', 'frozen': 'OPT'},
    'srv': {'sys': 'SRVS_DIR', 'user': 'USERMODE_SRVS_DIR', 'spec': '%h/.local/srv', 'frozen': 'SRV'},
    'etc': {'sys': 'ETCS_DIR', 'user': 'USERMODE_ETCS_DIR', 'spec': '%h/.config', 'frozen': 'ETC'},
    'var': {'sys': 'VARS_DIR', 'user': 'USERMODE_VARS_DIR', 'spec': '%h/.local/var/lib', 'frozen': 'VAR'},
    'log': {'sys': 'LOGS_DIR', 'user': 'USERMODE_LOGS_DIR', 'spec': '%h/.local/var/log', 'frozen': 'LOG'},
    'spool': {'sys': 'SPOOLS_DIR', 'user': 'USERMODE_SPOOLS_DIR', 'spec': '%h/.local/var/spool', 'frozen': 'SPOOL'},
    'cache': {'sys': 'CACHES_DIR', 'user': 'USERMODE_CACHES_DIR', 'spec': '%h/.cache', 'frozen': 'CACHE'},
    'src': {'sys': 'SRCS_DIR', 'user': 'USERMODE_SRCS_DIR', 'spec': '%h/src', 'frozen': 'SRC'},
    'pid': {'sys': 'PIDS_DIR', 'user': 'USERMODE_PIDS_DIR', 'spec': '%t', 'frozen': 'PID', 'user_runtime': True},
    'run': {'sys': 'RUNS_DIR', 'user': 'USERMODE_RUNS_DIR', 'spec': '%t', 'frozen': None, 'user_runtime': True},
    'share': {'sys': 'SHARES_DIR', 'user': 'USERMODE_SHARES_DIR', 'spec': '%h/.local/usr/share', 'frozen': 'SHARE'},
    'media': {'sys': 'MEDIAS_DIR', 'user': 'USERMODE_MEDIAS_DIR', 'spec': '%h/.local/media', 'frozen': None},
    # managed bins have no user-relative form: a global deploy keeps them global
    'bins': {'sys': 'BINS_DIR', 'user': 'USERMODE_BINS_DIR', 'spec': None, 'frozen': None},
    'global-bins': {'sys': 'GLOBAL_BINS_DIR', 'user': 'USERMODE_GLOBAL_BINS_DIR', 'spec': '%h/.local/bin', 'frozen': None},
}

FSH_ALIASES = {
    'vars': 'var',
    'etcs': 'etc',
    'srvs': 'srv',
    'opts': 'opt',
    'logs': 'log',
    'spools': 'spool',
    'caches': 'cache',
    'srcs': 'src',
    'pids': 'pid',
    'runs': 'run',
    'shares': 'share',
    'medias': 'media',
    'bin': 'bins',
    'global_bins': 'global-bins',
    'globalbins': 'global-bins',
}


def _truthy(value):
    if value is None:
        return False
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, (dict, list, set, tuple)):
        return bool(value)
    return str(value).strip().lower() in ('true', 'yes', 'on', '1')


class LookupModule(LookupBase):
    def _maybe_template(self, value):
        # variables may hand us lazy template strings (task vars like
        # _fsh_user arrive unrendered); template them before inspection
        if isinstance(value, str) and '{{' in value:
            try:
                return self._templar.template(value)
            except Exception:
                return value
        return value

    def run(self, terms, variables=None, **kwargs):
        if variables is None:
            raise AnsibleError("fsh lookup requires a variables context")
        if self._templar is None:
            raise AnsibleError("fsh lookup requires a templar")
        self._templar.available_variables = variables

        want_user = _truthy(kwargs.get('user', False))
        want_name = _truthy(kwargs.get('name', False))

        # USER_FSH flip: top-level opt-in, or the reserved _fsh_user set by
        # the systemd unit generation loop for user-scope separate renders.
        # Both may arrive as lazy template strings; template before truthiness.
        user_fsh = _truthy(self._maybe_template(variables.get('USER_FSH'))) or _truthy(
            self._maybe_template(variables.get('_fsh_user'))
        )
        overrides = {}
        if isinstance(variables.get('USER_FSH_DIRS'), dict):
            overrides.update(variables['USER_FSH_DIRS'])
        if isinstance(variables.get('USER_FSH'), dict):
            overrides.update(variables['USER_FSH'])

        results = []
        for term in terms if isinstance(terms, (list, tuple)) else [terms]:
            kind = FSH_ALIASES.get(str(term), str(term))
            if kind not in FSH_KINDS:
                raise AnsibleError(
                    "fsh lookup: unknown kind '{}' (known: {})".format(term, ', '.join(sorted(FSH_KINDS)))
                )
            entry = FSH_KINDS[kind]

            if user_fsh:
                base = overrides.get(kind, entry['spec'])
                if base is None:
                    base = self._base_var(entry['sys'], kind)
            elif want_user:
                user_var = entry.get('user')
                if user_var and user_var in variables:
                    base = variables[user_var]
                elif entry.get('user_runtime') and variables.get('XDG_RUNTIME_DIR'):
                    base = variables['XDG_RUNTIME_DIR']
                else:
                    base = overrides.get(kind, entry['spec'])
            else:
                base = self._base_var(entry['sys'], kind)

            base = self._templar.template(base)

            if want_name:
                frozen = None if (user_fsh or want_user) else entry.get('frozen')
                if frozen and frozen in variables:
                    value = self._templar.template(variables[frozen])
                else:
                    name = variables.get('NAME')
                    if name is None:
                        raise AnsibleError("fsh lookup: name=True but NAME is not defined")
                    value = base.rstrip('/') + '/' + str(self._templar.template(name))
            else:
                value = base
            results.append(value)
        return results

    def _base_var(self, var, kind):
        if var not in self._templar.available_variables:
            raise AnsibleError(
                "fsh lookup: '{}' is not defined (needed for kind '{}')".format(var, kind)
            )
        return self._templar.available_variables[var]
