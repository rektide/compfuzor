"""Helpers for retained, profile-independent Zim scratch demos."""

from __future__ import annotations

from pathlib import Path
import shlex


ZIM_RUNTIME_OVERRIDES = (
    "ZIM_CONFIG_FILE",
    "ZIM_ENV_CONFIG",
    "ZIM_CONFIG_LINK",
    "COMPFUZOR_ZIM_CONTEXT",
    "COMPFUZOR_ZIM_INSTALL_STRATEGY",
    "COMPFUZOR_ZIM_DROPINS_STRATEGY",
    "COMPFUZOR_CONFIG_INSTALL_STRATEGY",
    "COMPFUZOR_CONFIG_DROPINS_STRATEGY",
    "COMPFUZOR_CONFIG_CONTEXTS_BYPASS",
    "COMPFUZOR_CONFIG_BYPASS",
)


def write_environment_wrapper(wrapper: Path, values: dict[str, str]) -> None:
    exports = "\n".join(f"export {key}={shlex.quote(value)}" for key, value in values.items())
    unset = "unset " + " ".join(ZIM_RUNTIME_OVERRIDES)
    wrapper.write_text(f"#!/bin/sh\n{unset}\n{exports}\nexec \"$@\"\n", encoding="utf-8")
    wrapper.chmod(0o755)
