from __future__ import absolute_import, division, print_function

__metaclass__ = type

from jinja2 import pass_context

from _subsystem_utils import _context_var, _to_bool, _has_value, _has_payload


def build_install_bins(stem, basedir=False, src_root="../kernel"):
    """Return standard build/install bin entries for a stem.

    Example:
    - stem: "sysctl"
      -> build-sysctl.sh / install-sysctl.sh
    - stem: "kernel"
      -> build-kernel.sh / install-kernel.sh
    """
    stem_text = str(stem).strip()
    if not stem_text:
        return {"build_bins": [], "install_bins": []}

    return {
        "build_bins": [
            {
                "name": "build-{}.sh".format(stem_text),
                "src": "{}/build-{}.sh".format(src_root, stem_text),
                "basedir": basedir,
            }
        ],
        "install_bins": [
            {
                "name": "install-{}.sh".format(stem_text),
                "src": "{}/install-{}.sh".format(src_root, stem_text),
                "basedir": basedir,
            }
        ],
    }


@pass_context
def subsystem_record(
    context,
    subsystem,
    requested=None,
    bypassed=None,
    valid=None,
    errors=None,
    spec=None,
    contrib=None,
    status=None,
):
    """Build a subsystem runtime record with computed defaults.

    Purpose:
    - Keep subsystem state assembly consistent across tasks.
    - Avoid repeating base/status/active boilerplate in each subsystem block.

    Inclusion rules:
    - `spec` is attached only when valid + requested and payload is non-empty.
    - `contrib` is attached only when active and payload is non-empty.
    """
    resolved_errors = (
        errors if errors is not None else _context_var(context, "errors", [])
    )
    if resolved_errors is None:
        resolved_errors = []

    requested_bool = _to_bool(
        requested
        if requested is not None
        else _context_var(
            context, "_subsystem_requested", _context_var(context, "requested", False)
        )
    )
    bypassed_bool = _to_bool(
        bypassed
        if bypassed is not None
        else _context_var(
            context, "_subsystem_bypassed", _context_var(context, "bypassed", False)
        )
    )
    valid_bool = _to_bool(
        valid
        if valid is not None
        else _context_var(context, "_subsystem_valid", len(resolved_errors) == 0)
    )
    active_bool = requested_bool and (not bypassed_bool) and valid_bool

    resolved_status = (
        status if status is not None else _context_var(context, "_subsystem_status")
    )
    if resolved_status is None:
        if active_bool:
            resolved_status = "active"
        elif bypassed_bool:
            resolved_status = "bypassed"
        elif not valid_bool:
            resolved_status = "invalid"
        else:
            resolved_status = "requested"

    record = {
        "status": resolved_status,
        "requested": requested_bool,
        "bypassed": bypassed_bool,
        "valid": valid_bool,
        "active": active_bool,
        "reasons": resolved_errors,
    }

    if _has_value(subsystem):
        record["subsystem"] = subsystem

    if valid_bool and requested_bool and _has_payload(spec):
        record["spec"] = spec

    if active_bool and _has_payload(contrib):
        record["contrib"] = contrib

    return record


class FilterModule(object):
    def filters(self):
        return {
            "subsystem_record": subsystem_record,
            "build_install_bins": build_install_bins,
        }
