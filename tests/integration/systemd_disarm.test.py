#!/usr/bin/env python3

from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def test_systemd_phase_names_and_aliases() -> None:
    unit = (ROOT / "files/systemd/install-unit.sh").read_text(encoding="utf-8")
    dropin = (ROOT / "files/systemd/install-dropin.sh").read_text(encoding="utf-8")
    for phase in ("LINK", "ENABLE", "START"):
        canonical = f"COMPFUZOR_SYSTEMD_{phase}_BYPASS"
        alias = f"SYSTEMD_BYPASS_{phase}"
        if canonical not in unit or alias not in unit:
            raise AssertionError(f"install-unit.sh missing {canonical} or soak alias {alias}")
    for name in ("COMPFUZOR_SYSTEMD_LINK_BYPASS", "SYSTEMD_BYPASS_LINK"):
        if name not in dropin:
            raise AssertionError(f"install-dropin.sh missing {name}")
    subprocess.run(["bash", "-n", str(ROOT / "files/systemd/install-unit.sh")], check=True)
    subprocess.run(["bash", "-n", str(ROOT / "files/systemd/install-dropin.sh")], check=True)
    print("ok: systemd canonical phase flags and temporary aliases are present")


if __name__ == "__main__":
    test_systemd_phase_names_and_aliases()
