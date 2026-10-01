#!/usr/bin/env python3
"""Inspect scratch artifacts only; never grab input devices or apply units."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
render = root / ".test-agent/kinesis-kanata/render"
instances = sys.argv[1:] or ["edge-native", "edge-one-shot", "edge-command-layer"]
for instance in instances:
    name = f"kanata-{instance}"
    etc = render / "etc" / name
    cfg = etc / "kanata.kbd"
    subprocess.run(["kanata", "--check", "--cfg", str(cfg)], check=True)
    text = re.sub(r";;[^\n]*", "", cfg.read_text())
    assert "linux-output-device-name" not in text
    assert "process-unmapped-keys yes" in text
    assert '"Kinesis Freestyle Edge RGB Keyboard"' in text
    unit = (etc / f"{name}.service").read_text()
    assert f"ExecStart=/usr/bin/kanata --cfg {cfg}" in unit
    assert "PrivateNetwork=True" in unit and "NoNewPrivileges=True" in unit
    assert "Alias=" not in unit
    installer = (render / "srv" / name / "bin/install-service.sh").read_text()
    assert "UNIT_LINK_DEFAULT=link" in installer
    assert "--skip-start" in installer
    assert 'UNIT_ENABLE_TARGETS=""' in installer
    if instance == "b-merged":
        assert '"iRig BlueTurn Keyboard"' in text
        assert re.search(r"\(defsrc\s+caps f19 f20 f21 f22 pgup pgdn\s*\)", text)
        for layer in ("pages", "media"):
            match = re.search(rf"\(deflayer {layer}\s+([^()]*)", text)
            assert match and match[1].split()[:5] == ["@cap", "@pages", "@media", "lalt", "lmet"]
        assert re.search(r"\(deflayer pedal-meta\s+(?:_\s+){6}pp\s*\)", text)
    else:
        assert "iRig BlueTurn Keyboard" not in text
    if instance == "edge-one-shot":
        assert "(one-shot $modifier-timeout lalt)" in text
        assert "(one-shot $modifier-timeout lmet)" in text
    if instance == "edge-command-layer":
        assert "(deflayer base @cap f13 f14 f15 f16 lalt lmet @commands f24)" in text
        assert "(deflayer commands _ C-c C-v C-z C-S-z _ _ _ @hello)" in text
        assert "(macro h e l l o)" in text
    print(f"Checked {name}: config, unit, and link-only installer")
