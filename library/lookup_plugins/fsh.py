from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = """
    name: fsh
    author: compfuzor
    short_description: file-system-hierarchy aware directory lookup
    description:
      - Resolves a compfuzor directory kind (var, etc, srv, log, ...) to a
        base directory appropriate for the current mode, and composes.
      - Plain mode returns the deploy-mode base variable (VARS_DIR and
        friends), which under a USERMODE playbook is already the user
        hierarchy.
      - C(user=True) selects the user hierarchy. By default that means the
        USERMODE_*_DIR family resolved for the deploying user, so user-mode
        output stays consistent with a full USERMODE deploy.
      - The user hierarchy is defined as I(templates) rendered through the
        templar with a C(fsh_home)/C(fsh_runtime) context -- not fixed
        strings. Pass C(home=%h) (systemd unit directives) or
        C(home=${HOME}) (shell scripts and env files, expanded at runtime by
        the shell) to keep the output un-resolved and portable across
        users. C(runtime=) does the same for the per-user runtime dir
        (pid/run kinds), e.g. C(runtime=%t) or C(runtime=${XDG_RUNTIME_DIR}).
      - A top-level C(USER_FSH) variable flips the source to the user
        hierarchy when truthy; a string value ("C(%h)", "C(${HOME})")
        additionally supplies C(home=), a mapping may supply C(home=),
        C(runtime=) and a C(dirs) table. The systemd unit generation loop
        sets the reserved C(_fsh_user)/C(_fsh_home)/C(_fsh_runtime)
        variables for user-scope iterations of C(SYSTEMD_INSTALL=separate)
        renders, so a single SYSTEMD_SERVICES block renders system paths
        for the system unit and specifier paths for the user unit.
      - C(name=True) appends C(NAME); in plain mode a frozen hierarchy
        variable (VAR, ETC, SRV, ...) is preferred when present, matching
        the vars_hierarchy set_fact freeze.
      - The per-kind user templates can be overridden with a
        C(USER_FSH_DIRS) mapping variable; override values are templates
        too and may reference C({{fsh_home}}) and C({{fsh_runtime}}).
      - Kinds without a user form (only I(bins), where a global deploy keeps
        its managed bins global) fall back to the deploy-mode base even in
        user mode.
    options:
      user:
        description: Select the user hierarchy.
        type: boolean
        default: false
      name:
        description: Append NAME; prefer the frozen hierarchy variable in plain mode.
        type: boolean
        default: false
      home:
        description: Home substitution for user-hierarchy templates. Common
          values are C(%h) for systemd unit directives and the literal
          C(${HOME}) for shell-side runtime expansion. Unset resolves to the
          deploying user's home.
        type: string
      runtime:
        description: Runtime-dir substitution for pid/run kinds. Common
          values are C(%t) and the literal C(${XDG_RUNTIME_DIR}). Unset
          resolves to XDG_RUNTIME_DIR.
        type: string
"""

EXAMPLES = """
- name: Deploy-mode base dir (follows USERMODE flip)
  debug:
    msg: "{{ lookup('fsh', 'var') }}"

- name: Per-user state path, resolved for the deploying user
  debug:
    msg: "{{ lookup('fsh', 'var', user=True, name=True) }}"

- name: Same path for a systemd unit directive (systemd expands %h at load)
  debug:
    msg: "{{ lookup('fsh', 'var', user=True, name=True, home='%h') }}"

- name: Same path for a shell script or env file (shell expands at runtime)
  debug:
    msg: "{{ lookup('fsh', 'var', user=True, name=True, home='${HOME}') }}"

- name: Runtime dir kinds take runtime= instead
  debug:
    msg: "{{ lookup('fsh', 'pid', user=True, name=True, runtime='%t') }}"
"""

RETURN = """
_raw:
  description:
    - Resolved directory path(s), one per term. Values are templated;
      specifiers and shell variables in home=/runtime= pass through
      untouched for the consumer (systemd, shell) to expand.
  type: list
  elements: string
"""

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase

try:
    # ansible-core >= 2.19 trust model: only tagged template strings are
    # evaluated; tag our spec templates (they are plugin-authored constants
    # or USER_FSH_DIRS values, i.e. trusted sources).
    from ansible.template import trust_as_template as _trust_as_template
except ImportError:  # pragma: no cover - older ansible-core
    def _trust_as_template(value):
        return value

# kind -> columns
#   sys:    deploy-mode base variable (VARS_DIR and friends)
#   um:     USERMODE_*_DIR family member (resolved-user parity)
#   spec:   user-hierarchy template; may reference {{fsh_home}}/{{fsh_runtime}}
#   frozen: implicit hierarchy var from vars_hierarchy.tasks (VAR, ETC, ...)
FSH_KINDS = {
    'opt': {'sys': 'OPTS_DIR', 'um': 'USERMODE_OPTS_DIR', 'spec': '{{fsh_home}}/.local/opt', 'frozen': 'OPT'},
    'srv': {'sys': 'SRVS_DIR', 'um': 'USERMODE_SRVS_DIR', 'spec': '{{fsh_home}}/.local/srv', 'frozen': 'SRV'},
    'etc': {'sys': 'ETCS_DIR', 'um': 'USERMODE_ETCS_DIR', 'spec': '{{fsh_home}}/.config', 'frozen': 'ETC'},
    'var': {'sys': 'VARS_DIR', 'um': 'USERMODE_VARS_DIR', 'spec': '{{fsh_home}}/.local/var/lib', 'frozen': 'VAR'},
    'log': {'sys': 'LOGS_DIR', 'um': 'USERMODE_LOGS_DIR', 'spec': '{{fsh_home}}/.local/var/log', 'frozen': 'LOG'},
    'spool': {'sys': 'SPOOLS_DIR', 'um': 'USERMODE_SPOOLS_DIR', 'spec': '{{fsh_home}}/.local/var/spool', 'frozen': 'SPOOL'},
    'cache': {'sys': 'CACHES_DIR', 'um': 'USERMODE_CACHES_DIR', 'spec': '{{fsh_home}}/.cache', 'frozen': 'CACHE'},
    'src': {'sys': 'SRCS_DIR', 'um': 'USERMODE_SRCS_DIR', 'spec': '{{fsh_home}}/src', 'frozen': 'SRC'},
    'pid': {'sys': 'PIDS_DIR', 'um': None, 'spec': '{{fsh_runtime}}', 'frozen': 'PID'},
    'run': {'sys': 'RUNS_DIR', 'um': None, 'spec': '{{fsh_runtime}}', 'frozen': None},
    'share': {'sys': 'SHARES_DIR', 'um': 'USERMODE_SHARES_DIR', 'spec': '{{fsh_home}}/.local/usr/share', 'frozen': 'SHARE'},
    'media': {'sys': 'MEDIAS_DIR', 'um': 'USERMODE_MEDIAS_DIR', 'spec': '{{fsh_home}}/.local/media', 'frozen': None},
    # managed bins have no user form: a global deploy keeps them global
    'bins': {'sys': 'BINS_DIR', 'um': 'USERMODE_BINS_DIR', 'spec': None, 'frozen': None},
    'global-bins': {'sys': 'GLOBAL_BINS_DIR', 'um': 'USERMODE_GLOBAL_BINS_DIR', 'spec': '{{fsh_home}}/.local/bin', 'frozen': None},
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


def _unset(value):
    return value is None or value == '' or value is False


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        if variables is None:
            raise AnsibleError("fsh lookup requires a variables context")
        if self._templar is None:
            raise AnsibleError("fsh lookup requires a templar")
        self._templar.available_variables = variables

        want_user = _truthy(kwargs.get('user', False))
        want_name = _truthy(kwargs.get('name', False))

        # USER_FSH: truthy flips the source; a string supplies home=; a
        # mapping may supply home=/runtime=/dirs.
        user_fsh = self._maybe_template(variables.get('USER_FSH'))
        # _fsh_user is reserved for the systemd unit generation loop; when
        # present (even False) it decides the mode outright -- False forces
        # the system hierarchy so one SYSTEMD_SERVICES block serves both
        # units.
        fsh_user = self._maybe_template(variables.get('_fsh_user'))

        overrides = {}
        if isinstance(variables.get('USER_FSH_DIRS'), dict):
            overrides.update(variables['USER_FSH_DIRS'])
        if isinstance(user_fsh, dict) and isinstance(user_fsh.get('dirs'), dict):
            overrides.update(user_fsh['dirs'])

        if fsh_user is not None and fsh_user != '':
            user_mode = _truthy(fsh_user)
        elif not _unset(user_fsh):
            user_mode = True
        else:
            user_mode = want_user

        home = kwargs.get('home')
        runtime = kwargs.get('runtime')
        if _unset(home):
            home = self._maybe_template(variables.get('_fsh_home'))
        if _unset(home) and isinstance(user_fsh, str) and user_fsh:
            home = user_fsh
        if _unset(home) and isinstance(user_fsh, dict):
            home = self._maybe_template(user_fsh.get('home'))
        if _unset(runtime):
            runtime = self._maybe_template(variables.get('_fsh_runtime'))
        if _unset(runtime) and isinstance(user_fsh, dict):
            runtime = self._maybe_template(user_fsh.get('runtime'))

        parameterized = not _unset(home) or not _unset(runtime)

        results = []
        for term in terms if isinstance(terms, (list, tuple)) else [terms]:
            kind = FSH_ALIASES.get(str(term), str(term))
            if kind not in FSH_KINDS:
                raise AnsibleError(
                    "fsh lookup: unknown kind '{}' (known: {})".format(term, ', '.join(sorted(FSH_KINDS)))
                )
            entry = FSH_KINDS[kind]

            if user_mode:
                base = self._user_base(kind, entry, overrides, parameterized, home, runtime)
            else:
                base = self._templar.template(self._base_var(entry['sys'], kind))

            if want_name:
                frozen = None if user_mode else entry.get('frozen')
                if frozen and frozen in variables:
                    value = self._templar.template(variables[frozen])
                else:
                    name = variables.get('NAME')
                    if name is None:
                        raise AnsibleError("fsh lookup: name=True but NAME is not defined")
                    value = str(base).rstrip('/') + '/' + str(self._templar.template(name))
            else:
                value = base
            results.append(value)
        return results

    def _user_base(self, kind, entry, overrides, parameterized, home, runtime):
        if kind in overrides:
            return self._render_spec(str(overrides[kind]), kind, home, runtime)
        spec = entry['spec']
        if spec is None:
            # no user form (bins): fall back to the deploy-mode base
            return self._templar.template(self._base_var(entry['sys'], kind))
        um = entry.get('um')
        # unparameterized + USERMODE family defined: match a full USERMODE
        # deploy's resolved dirs (their exact conventions win over the table)
        if not parameterized and um and um in self._templar.available_variables:
            return self._templar.template(self._templar.available_variables[um])
        return self._render_spec(spec, kind, home, runtime)

    def _render_spec(self, spec, kind, home, runtime):
        ctx = {}
        if '{{fsh_home}}' in spec:
            if _unset(home):
                home = self._templar.available_variables.get('HOMEDIR')
            if _unset(home):
                raise AnsibleError(
                    "fsh lookup: kind '{}' needs a home; pass home= or set HOMEDIR".format(kind)
                )
            ctx['fsh_home'] = str(home).rstrip('/')
        if '{{fsh_runtime}}' in spec:
            if _unset(runtime):
                runtime = self._templar.available_variables.get('XDG_RUNTIME_DIR')
            if _unset(runtime):
                raise AnsibleError(
                    "fsh lookup: kind '{}' needs a runtime dir; pass runtime= or set XDG_RUNTIME_DIR".format(kind)
                )
            ctx['fsh_runtime'] = str(runtime).rstrip('/')
        if not ctx:
            return spec
        merged = dict(self._templar.available_variables or {})
        merged.update(ctx)
        saved = self._templar.available_variables
        self._templar.available_variables = merged
        try:
            return self._templar.template(_trust_as_template(spec))
        finally:
            self._templar.available_variables = saved

    def _base_var(self, var, kind):
        if var not in self._templar.available_variables:
            raise AnsibleError(
                "fsh lookup: '{}' is not defined (needed for kind '{}')".format(var, kind)
            )
        return self._templar.available_variables[var]

    def _maybe_template(self, value):
        # variables may hand us lazy template strings (task vars like
        # _fsh_home arrive unrendered); template them before inspection
        if isinstance(value, str) and '{{' in value:
            try:
                return self._templar.template(value)
            except Exception:
                return value
        return value
