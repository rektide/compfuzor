#!/usr/bin/env python3
"""Retained demo wrappers isolate Zim output selectors from the invoking shell."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile

from zim_demo import write_environment_wrapper


def resolved_values(wrapper: Path, hostile: dict[str, str]) -> list[str]:
    probe = r'''printf '%s\n' \
"${ZIM_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimrc}" \
"${ZIM_ENV_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimenv}" \
"${ZIM_CONFIG_LINK:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimfw.conf}" \
"${TMPDIR}"'''
    result = subprocess.run([str(wrapper), "/bin/sh", "-c", probe], env=hostile, text=True, capture_output=True, check=True)
    return result.stdout.splitlines()


def test_demo_wrapper_environment_isolation() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-zim-demo-wrapper-") as tmp:
        root = Path(tmp)
        scratch_tmp = root / "tmp"
        scratch_tmp.mkdir()
        home_one = root / "home-one"
        xdg_one = root / "xdg-one"
        user_one = root / "user-one.sh"
        write_environment_wrapper(user_one, {
            "HOME": str(home_one),
            "XDG_CONFIG_HOME": str(xdg_one),
            "TMPDIR": str(scratch_tmp),
        })

        home_two = root / "home-two"
        xdg_two = root / "xdg-two"
        custom = home_two / "custom"
        user_two = root / "user-two.sh"
        write_environment_wrapper(user_two, {
            "HOME": str(home_two),
            "XDG_CONFIG_HOME": str(xdg_two),
            "TMPDIR": str(scratch_tmp),
            "ZIM_CONFIG_FILE": str(custom / "runtime.zimrc"),
            "ZIM_ENV_CONFIG": str(custom / "runtime.zimenv"),
            "ZIM_CONFIG_LINK": str(custom / "zimfw.conf"),
        })

        hostile = os.environ.copy()
        hostile.update({
            "ZIM_CONFIG_FILE": "/real/profile/zimrc",
            "ZIM_ENV_CONFIG": "/real/profile/zimenv",
            "ZIM_CONFIG_LINK": "/real/profile/zimfw.conf",
            "TMPDIR": "/real/profile/tmp",
        })
        assert resolved_values(user_one, hostile) == [
            str(xdg_one / "zsh" / "zimrc"),
            str(xdg_one / "zsh" / "zimenv"),
            str(xdg_one / "zsh" / "zimfw.conf"),
            str(scratch_tmp),
        ]
        assert resolved_values(user_two, hostile) == [
            str(custom / "runtime.zimrc"),
            str(custom / "runtime.zimenv"),
            str(custom / "zimfw.conf"),
            str(scratch_tmp),
        ]


if __name__ == "__main__":
    test_demo_wrapper_environment_isolation()
    print("ok: retained Zim demo wrapper isolation")
