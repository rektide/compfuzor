"""Owner-held descriptors and invocation-bound registration endpoints, never rendezvous writes at render."""
from __future__ import annotations
import posixpath
import re
import shlex
from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers
from template_data import raw_copy_template_data
from runtime_bundles import compfuzor_runtime_bins
from config_selectors import compile_path_selector

def compile_registry_policy(raw):
    if not isinstance(raw, dict) or raw.get("version") != 1 or not isinstance(raw.get("audiences"), dict):
        raise AnsibleFilterError("registry policy requires version 1 and audiences")
    audiences = {}
    for audience, pair in raw["audiences"].items():
        if audience not in ("user", "system") or not isinstance(pair, dict) or set(pair) != {"providers", "consumers"}:
            raise AnsibleFilterError("registry policy audience requires both providers and consumers")
        audiences[audience] = {}
        for role, roots in pair.items():
            if not isinstance(roots, dict) or set(roots) != {"roots", "writeRoot"} or not isinstance(roots["roots"], list) or not roots["roots"]:
                raise AnsibleFilterError("registry policy role requires nonempty roots and writeRoot")
            audiences[audience][role] = {"roots": [compile_path_selector(value, "registry root") for value in roots["roots"]], "writeRoot": compile_path_selector(roots["writeRoot"], "registry write root")}
    return {"version": 1, "audiences": audiences}

def registration_bins(owner, collection, source, scope, registry_policy=None):
    bins = []
    for action in ("register", "status"):
        args = ["registry", action, "--collection", collection, "--scope", scope, "--source", source]
        if registry_policy:
            args.extend(["--registry-policy", registry_policy])
        bins.append({"name": action + "-" + owner + ".sh", "scope": [scope], "run": False, "compose": False,
            "basedir": False, "deployment_rooted": True, "content": 'exec "$DIR/bin/compfuzor-runtime.mjs" ' + " ".join(shlex.quote(arg) for arg in args) + ' "$@"'})
    return bins

@accept_args_markers
def zim_registry(fragments, producer, etc):
    fragments = raw_copy_template_data(fragments)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", producer):
        raise AnsibleFilterError("zim registry requires a stable producer id")
    exact = []
    for record in fragments:
        name = record["name"]
        match = re.fullmatch(r"zim/(zimrc|zimenv)/(active|disabled)/([^/]+\.conf)", name)
        if match:
            channel, state, filename = match.groups()
            exact.append({"channel": channel, "name": filename, "path": posixpath.join(etc, name), "enabled": state == "active"})
    source = posixpath.join(etc, "zim-provider.json")
    return {"files": [{"name": "zim-provider.json", "json": {"version": 1, "id": producer, "fragments": exact}}],
        "bins": compfuzor_runtime_bins() + registration_bins("zim-provider", "zim-providers", source, "user")}

class FilterModule(object):
    def filters(self):
        return {"zim_registry": zim_registry}
