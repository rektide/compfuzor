from __future__ import annotations

DOCUMENTATION = """
    name: playbook_identity
    author: compfuzor
    short_description: Resolve deployment identity and playbook source provenance
    description:
      - Uses the resolved Compfuzor C(NAME) as authoritative deployment identity.
      - Resolves source provenance from C(COMPFUZOR_PLAYBOOK_PATH), then Ansible
        CLI playbook arguments, then the legacy process command line.
      - Retains multiple candidates as ambiguous rather than choosing one.
"""

import os
import shlex

from ansible import context
from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase


def _playbook_candidates(values):
    result = []
    for value in values or []:
        if not isinstance(value, str) or not value.endswith(".pb"):
            continue
        path = os.path.abspath(value)
        if path not in result:
            result.append(path)
    return result


def _legacy_args(cmdline):
    if not isinstance(cmdline, str) or not cmdline:
        return []
    if "\0" in cmdline:
        return [value for value in cmdline.split("\0") if value]
    try:
        return shlex.split(cmdline)
    except ValueError:
        return cmdline.split()


def resolve_playbook_identity(variables, cliargs=None, cmdline=None):
    variables = variables or {}
    name = variables.get("NAME")
    if not isinstance(name, str) or not name.strip():
        raise AnsibleError("playbook_identity requires resolved Compfuzor NAME")
    name = name.strip()

    explicit = variables.get("COMPFUZOR_PLAYBOOK_PATH")
    if isinstance(explicit, str) and explicit.strip():
        candidates = _playbook_candidates([explicit.strip()])
        resolution = "explicit"
    else:
        args = (cliargs or {}).get("args", []) if isinstance(cliargs, dict) else []
        candidates = _playbook_candidates(args)
        resolution = "ansible-cliargs"
        if not candidates:
            candidates = _playbook_candidates(_legacy_args(cmdline))
            resolution = "legacy-cmdline" if candidates else "unknown"

    confidence = "exact" if len(candidates) == 1 else "ambiguous" if candidates else "unknown"
    source = {
        "resolution": resolution,
        "confidence": confidence,
        "candidates": candidates,
    }
    if len(candidates) == 1:
        source["playbook"] = candidates[0]

    deployment = {
        "id": "deployment:{}".format(name),
        "kind": "deployment",
        "name": name,
        "source": source,
    }
    for source_name, target_name in (
        ("TYPE", "type"),
        ("INSTANCE", "instance"),
        ("SUBINSTANCE", "subinstance"),
        ("DIR", "dir"),
        ("ansible_play_name", "playName"),
    ):
        value = variables.get(source_name)
        if isinstance(value, str) and value:
            deployment[target_name] = value
    return deployment


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        if terms:
            raise AnsibleError("lookup('playbook_identity') accepts no positional terms")
        try:
            cmdline = open("/proc/self/cmdline", "rb").read().decode(errors="replace")
        except OSError:
            cmdline = ""
        return [
            resolve_playbook_identity(
                variables,
                cliargs=dict(context.CLIARGS),
                cmdline=cmdline,
            )
        ]
