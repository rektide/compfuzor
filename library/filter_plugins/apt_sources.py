"""Render freeform deb822 apt sources and preferences stanzas.

Only the small set of fields needed for safe defaults is understood here;
other apt fields are emitted as authored, without a compfuzor field registry.
"""

from collections.abc import Mapping
import re

from ansible.errors import AnsibleFilterError


_FIELD = re.compile(r"^[A-Za-z][A-Za-z0-9-]*$")
_CANONICAL = {
    name.lower(): name
    for name in (
        "Types", "URIs", "Suites", "Components", "Signed-By", "Architectures",
        "Trusted", "Enabled", "Package", "Pin", "Pin-Priority",
    )
}


def _stanza(spec, defaults, required):
    if not isinstance(spec, Mapping):
        raise AnsibleFilterError("apt deb822 stanza must be a mapping")
    if not isinstance(defaults, Mapping):
        raise AnsibleFilterError("apt deb822 defaults must be a mapping")
    fields = {}
    for source in (defaults, spec):
        for name, value in source.items():
            if not isinstance(name, str) or not _FIELD.fullmatch(name):
                raise AnsibleFilterError(f"invalid apt field name: {name!r}")
            key = _CANONICAL.get(name.lower(), name)
            fields[key.lower()] = (key, value)
    for field in required:
        if field.lower() not in fields or fields[field.lower()][1] in (None, False, "", []):
            raise AnsibleFilterError(f"apt deb822 stanza requires {field}")
    rows = []
    for name, value in fields.values():
        if value is None or value == [] or (name.lower() == "components" and value is False):
            continue
        if isinstance(value, (tuple, list)):
            if not value or any(not isinstance(part, (str, int)) or "\n" in str(part) for part in value):
                raise AnsibleFilterError(f"invalid apt {name} list")
            value = " ".join(map(str, value))
        elif value is True:
            value = "yes"
        elif value is False:
            value = "no"
        elif not isinstance(value, (str, int)):
            raise AnsibleFilterError(f"invalid apt {name} value: {value!r}")
        value = str(value)
        if "\r" in value:
            raise AnsibleFilterError(f"invalid apt {name} value: carriage return")
        if "\n" in value:
            if name.lower() != "signed-by" or not value.lstrip().startswith("-----BEGIN PGP PUBLIC KEY BLOCK-----") or "-----END PGP PUBLIC KEY BLOCK-----" not in value:
                raise AnsibleFilterError(f"multiline apt {name} is not an inline PGP key")
            # RFC822 continuation lines; apt requires blank key lines to be
            # encoded as a single dot (sources.list(5)).
            rows.append(f"{name}:\n" + "\n".join(" " + (line or ".") for line in value.strip().splitlines()))
        else:
            rows.append(f"{name}: {value}")
    return "\n".join(rows)


def apt_sources(specs, defaults=None, signed_by=None):
    """Render source stanza list, deriving Signed-By only for acquired keys."""
    if not isinstance(specs, list) or not specs:
        raise AnsibleFilterError("APT/APTS must declare at least one source stanza")
    base = {"Types": "deb", **(defaults or {})}
    if signed_by and not any(name.lower() == "signed-by" for name in base):
        base["Signed-By"] = signed_by
    return "\n\n".join(_stanza(spec, base, ("Types", "URIs", "Suites")) for spec in specs) + "\n"


def apt_preferences(specs):
    """Render freeform apt preferences stanzas with Package defaulting to *."""
    if isinstance(specs, Mapping):
        specs = [specs]
    if not isinstance(specs, list) or not specs:
        raise AnsibleFilterError("APT_PREFS must be a nonempty mapping or list")
    return "\n\n".join(_stanza(spec, {"Package": "*"}, ("Package", "Pin", "Pin-Priority")) for spec in specs) + "\n"


class FilterModule:
    def filters(self):
        return {"apt_sources": apt_sources, "apt_preferences": apt_preferences}
