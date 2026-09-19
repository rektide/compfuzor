"""Canonical omnibus runtime records shared by generated consumers."""

from __future__ import annotations

import posixpath
from pathlib import Path

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers


_REPOSITORY = Path(__file__).resolve().parents[2]
_RUNTIME_ARTIFACT = "compfuzor-runtime.mjs"


def runtime_artifact_bin(artifact, name):
    """Return one checked-in Vite+ runtime artifact or fail before rendering."""
    source = _REPOSITORY / "runtime" / artifact
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


def compfuzor_runtime_bin():
    """Return the canonical compatible claim for the omnibus runtime."""
    return runtime_artifact_bin(_RUNTIME_ARTIFACT, _RUNTIME_ARTIFACT)


def runtime_alias_bin(name):
    """Return one stable command alias to the omnibus runtime."""
    if not isinstance(name, str) or not name or posixpath.isabs(name):
        raise AnsibleFilterError("runtime alias must be a non-empty relative path")
    return {
        "name": name,
        "dest": name,
        "link": _RUNTIME_ARTIFACT,
        "compose": False,
        "basedir": False,
    }


def compfuzor_runtime_bins(*aliases):
    """Return one artifact claim and stable aliases for a runtime consumer."""
    return [compfuzor_runtime_bin()] + [runtime_alias_bin(name) for name in aliases]


@accept_args_markers
def links_runtime_bins(full=False):
    """Return no delivery code or a complete omnibus runtime plus LINKS aliases."""
    if full not in (True, False, None):
        raise AnsibleFilterError("links_runtime_bins expects a boolean or None")
    if not full:
        return []
    return compfuzor_runtime_bins("links/links.mjs", "links.mjs")


@accept_args_markers
def links_runtime_dirs(bins_dir):
    """Return the directory required by the nested LINKS compatibility alias."""
    if not isinstance(bins_dir, str) or not bins_dir:
        raise AnsibleFilterError("links_runtime_dirs requires a non-empty BINS_DIR")
    return [posixpath.join(bins_dir, "links")]


class FilterModule(object):
    def filters(self):
        return {
            "compfuzor_runtime_bins": compfuzor_runtime_bins,
            "links_runtime_bins": links_runtime_bins,
            "links_runtime_dirs": links_runtime_dirs,
        }
