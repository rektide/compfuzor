"""Helpers for retained, profile-independent Zim scratch demos."""

from __future__ import annotations

from pathlib import Path
import shlex


ZIM_OUTPUT_OVERRIDES = ("ZIM_CONFIG_FILE", "ZIM_ENV_CONFIG", "ZIM_CONFIG_LINK")


def write_environment_wrapper(wrapper: Path, values: dict[str, str]) -> None:
    exports = "\n".join(f"export {key}={shlex.quote(value)}" for key, value in values.items())
    unset = "unset " + " ".join(ZIM_OUTPUT_OVERRIDES)
    wrapper.write_text(f"#!/bin/sh\n{unset}\n{exports}\nexec \"$@\"\n", encoding="utf-8")
    wrapper.chmod(0o755)
