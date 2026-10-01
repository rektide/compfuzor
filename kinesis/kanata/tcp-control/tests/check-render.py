#!/usr/bin/python3
"""Check actual render-only artifacts; run from the repository root."""
from pathlib import Path

ROOT = Path(".test-agent/kinesis-kanata/render")
for name in ("a-keyboard", "a-keyboard-hotkeys", "a-pedal"):
    etc = ROOT / "etc" / f"kanata-{name}"
    unit = (etc / f"kanata-{name}.service").read_text()
    cfg = (etc / "kanata.kbd").read_text()
    assert "Alias=" not in unit
    assert "PrivateUsers=True" in unit
    assert "linux-output-device-name" not in cfg
    if name != "a-keyboard-hotkeys":
        for directive in ("PrivateNetwork=no", "RestrictAddressFamilies=AF_INET",
                          "IPAddressDeny=any", "IPAddressAllow=localhost", "ExecStartPre="):
            assert directive in unit, (name, directive)
    if name == "a-pedal":
        assert "--port 127.0.0.1:16666" in unit
        assert '"iRig BlueTurn Keyboard"' in cfg
        for layer in ("base", "pages", "media", "pedal-meta"):
            assert f"(deflayer {layer}" in cfg
    else:
        assert '"Kinesis Freestyle Edge RGB Keyboard"' in cfg
        assert "(tap-hold 100 100 esc lctl)" in cfg
        helper = etc / "blueturn-switch"
        assert helper.stat().st_mode & 0o111
        source = Path("kinesis/kanata/tcp-control/scripts/blueturn-switch")
        # Ansible's file lookup strips the trailing newline.
        assert helper.read_text().rstrip() == source.read_text().rstrip()
        assert ("(cmd " in cfg) == (name == "a-keyboard")
    installer = ROOT / "srv" / f"kanata-{name}" / "bin" / "install-service.sh"
    text = installer.read_text()
    assert 'UNIT_ENABLE_TARGETS=""' in text
    assert "--skip-start" in text
build = ROOT / "src" / "kanata-a-build" / "bin" / "build-kanata.sh"
assert "--features tcp_server,cmd" in build.read_text()
print("render artifacts: three configs/units, staged helpers, link-only installers, private build OK")
