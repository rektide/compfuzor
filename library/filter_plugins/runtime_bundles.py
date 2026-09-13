"""Small canonical module bundles shared by generated runtime consumers."""

from __future__ import annotations

import posixpath

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers


_DELIVERY = {
    "name": "links/delivery.ts",
    "src": "../links/delivery.ts",
    "raw": True,
    "compose": False,
    "basedir": False,
}

_MANAGER = (
    {
        "name": "links.ts",
        "src": "../links.ts",
        "raw": True,
        "compose": False,
        "basedir": False,
    },
    {
        "name": "links/links.ts",
        "src": "../links/links.ts",
        "raw": True,
        "compose": False,
        "basedir": False,
    },
    {
        "name": "links/cli.ts",
        "src": "../links/cli.ts",
        "raw": True,
        "compose": False,
        "basedir": False,
    },
    {
        "name": "links/manifest.ts",
        "src": "../links/manifest.ts",
        "raw": True,
        "compose": False,
        "basedir": False,
    },
)


@accept_args_markers
def links_runtime_bins(full=False):
    """Return the delivery-only or full LINKS raw TypeScript module bundle."""
    if full not in (True, False, None):
        raise AnsibleFilterError("links_runtime_bins expects a boolean or None")
    records = list(_MANAGER) + [_DELIVERY] if full else [_DELIVERY]
    return [dict(record) for record in records]


@accept_args_markers
def links_runtime_dirs(bins_dir):
    """Return the directory required by either LINKS runtime bundle."""
    if not isinstance(bins_dir, str) or not bins_dir:
        raise AnsibleFilterError("links_runtime_dirs requires a non-empty BINS_DIR")
    return [posixpath.join(bins_dir, "links")]


class FilterModule(object):
    def filters(self):
        return {
            "links_runtime_bins": links_runtime_bins,
            "links_runtime_dirs": links_runtime_dirs,
        }
