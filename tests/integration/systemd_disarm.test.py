#!/usr/bin/env python3

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
UNIT_SCRIPT = ROOT / "files/systemd/install-unit.sh"
DROPIN_TEMPLATE = ROOT / "files/systemd/install-dropin.sh"
BYPASS_VARIABLES = (
    "COMPFUZOR_SYSTEMD_BYPASS",
    "COMPFUZOR_SYSTEMD_INSTALL_DROPIN_BYPASS",
    "COMPFUZOR_SYSTEMD_LINK_BYPASS",
    "COMPFUZOR_SYSTEMD_ENABLE_BYPASS",
    "COMPFUZOR_SYSTEMD_START_BYPASS",
    "SYSTEMD_BYPASS_LINK",
    "SYSTEMD_BYPASS_ENABLE",
    "SYSTEMD_BYPASS_START",
)


def clean_env() -> dict[str, str]:
    env = os.environ.copy()
    for variable in BYPASS_VARIABLES:
        env.pop(variable, None)
    env["ENV_BYPASS"] = "1"
    return env


def fake_systemctl(temporary: Path) -> tuple[Path, Path]:
    log = temporary / "systemctl.log"
    command = temporary / "systemctl"
    command.write_text(
        "#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"$SYSTEMCTL_LOG\"\n",
        encoding="utf-8",
    )
    command.chmod(0o755)
    return command, log


def run_unit(
    temporary: Path,
    variable: str,
    *,
    enable_targets: str,
) -> tuple[subprocess.CompletedProcess, list[str], Path]:
    command, log = fake_systemctl(temporary)
    source = temporary / "test.service"
    source.write_text("[Service]\nExecStart=/bin/true\n", encoding="utf-8")
    destination = temporary / "units/test.service"
    env = clean_env()
    env.update(
        {
            variable: "1",
            "UNIT_TEMPLATE": "test",
            "UNIT_TYPE": "service",
            "UNIT_DIR": str(destination.parent),
            "UNIT_SRC": str(source),
            "UNIT_DEST": str(destination),
            "UNIT_ENABLE_TARGETS": enable_targets,
            "SUDO_CMD": "",
            "SYSTEMCTL": str(command),
            "SYSTEMCTL_LOG": str(log),
        }
    )
    result = subprocess.run(
        ["bash", str(UNIT_SCRIPT)],
        check=True,
        text=True,
        capture_output=True,
        env=env,
    )
    calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
    return result, calls, destination


def render_dropin(temporary: Path) -> tuple[Path, Path]:
    command, log = fake_systemctl(temporary)
    unit_dir = temporary / "units"
    row = f'  "sample|demo.service|{unit_dir}|{command}|-"'
    rendered = DROPIN_TEMPLATE.read_text(encoding="utf-8").replace(
        "{{ _dropin_rows }}", row
    )
    script = temporary / "install-dropin.sh"
    script.write_text(rendered, encoding="utf-8")
    return script, log


def test_systemd_phase_names_and_aliases() -> None:
    subprocess.run(["bash", "-n", str(UNIT_SCRIPT)], check=True)

    with tempfile.TemporaryDirectory(prefix="compfuzor-systemd-disarm-") as tmp:
        temporary = Path(tmp)
        for variable in (
            "COMPFUZOR_SYSTEMD_LINK_BYPASS",
            "SYSTEMD_BYPASS_LINK",
        ):
            case = temporary / variable.lower()
            case.mkdir()
            result, calls, destination = run_unit(
                case, variable, enable_targets=""
            )
            if "Bypassed linking" not in result.stdout or destination.exists():
                raise AssertionError(f"{variable} did not bypass linking: {result!r}")
            if calls:
                raise AssertionError(f"{variable} called systemctl: {calls!r}")

        for variable in (
            "COMPFUZOR_SYSTEMD_ENABLE_BYPASS",
            "SYSTEMD_BYPASS_ENABLE",
        ):
            case = temporary / variable.lower()
            case.mkdir()
            result, calls, destination = run_unit(
                case, variable, enable_targets="test"
            )
            if "Bypassed enabling" not in result.stdout or not destination.is_symlink():
                raise AssertionError(f"{variable} did not stop after linking: {result!r}")
            if calls != ["daemon-reload"]:
                raise AssertionError(f"{variable} unexpectedly enabled a unit: {calls!r}")

        for variable in (
            "COMPFUZOR_SYSTEMD_START_BYPASS",
            "SYSTEMD_BYPASS_START",
        ):
            case = temporary / variable.lower()
            case.mkdir()
            _, calls, _ = run_unit(case, variable, enable_targets="test")
            if calls != ["daemon-reload", "enable test"]:
                raise AssertionError(
                    f"{variable} did not enable without --now: {calls!r}"
                )

        dropin_case = temporary / "dropin"
        dropin_case.mkdir()
        dropin_script, dropin_log = render_dropin(dropin_case)
        subprocess.run(["bash", "-n", str(dropin_script)], check=True)
        for variable in (
            "COMPFUZOR_SYSTEMD_BYPASS",
            "COMPFUZOR_SYSTEMD_INSTALL_DROPIN_BYPASS",
            "COMPFUZOR_SYSTEMD_LINK_BYPASS",
            "SYSTEMD_BYPASS_LINK",
        ):
            if dropin_log.exists():
                dropin_log.unlink()
            env = clean_env()
            env[variable] = "1"
            env["SYSTEMCTL_LOG"] = str(dropin_log)
            result = subprocess.run(
                ["bash", str(dropin_script)],
                check=True,
                text=True,
                capture_output=True,
                env=env,
            )
            if "Bypassed" not in result.stdout:
                raise AssertionError(f"drop-in ignored {variable}: {result!r}")
            if dropin_log.exists():
                raise AssertionError(f"drop-in {variable} called systemctl")
            if (dropin_case / "units").exists():
                raise AssertionError(f"drop-in {variable} touched the unit directory")

    print("ok: systemd broad, nested, and canonical/alias phases are behavioral")


if __name__ == "__main__":
    test_systemd_phase_names_and_aliases()
