"""Owner-held descriptors and invocation-bound registration endpoints, never rendezvous writes at render."""
from __future__ import annotations
import posixpath
import re
import shlex
from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers
from template_data import raw_copy_template_data
from runtime_bundles import compfuzor_runtime_bins

def registration_bins(owner, collection, source, scope):
    bins = []
    for action in ("register", "status"):
        args = ["registry", action, "--collection", collection, "--scope", scope, "--source", source]
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
