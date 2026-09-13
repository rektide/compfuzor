"""Small canonical module bundles shared by generated runtime consumers."""

from __future__ import annotations

import posixpath
from pathlib import Path

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers


_REPOSITORY = Path(__file__).resolve().parents[2]


def runtime_artifact_bin(artifact, name):
    """Return one checked-in Vite+ runtime artifact or fail before rendering."""
    source = _REPOSITORY / "build" / "runtime" / artifact
    if not source.is_file():
        raise AnsibleFilterError(
            "missing built runtime {}: run `pnpm install` and `pnpm build` in {}".format(
                artifact, _REPOSITORY
            )
        )
    return {
        "name": name,
        "src": str(source),
        "raw": True,
        "compose": False,
        "basedir": False,
    }


@accept_args_markers
def links_runtime_bins(full=False):
    """Return no standalone delivery code or the complete built LINKS runtime."""
    if full not in (True, False, None):
        raise AnsibleFilterError("links_runtime_bins expects a boolean or None")
    if not full:
        return []
    return [
        runtime_artifact_bin("links/links.mjs", "links/links.mjs"),
        {
            "name": "links.mjs",
            "link": "links/links.mjs",
            "compose": False,
            "basedir": False,
        },
    ]


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
