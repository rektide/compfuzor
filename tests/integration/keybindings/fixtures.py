"""Shared disposable registry policies and complete XDG isolation for native proofs."""
from pathlib import Path


def registry_policy():
    # Portable selectors deliberately bind at invocation, not on the controller.
    return {"version": 1, "audiences": {
        audience: {role: {"roots": ["${HOME}/registries/" + audience + "/" + role + ".d"],
                          "writeRoot": "${HOME}/registries/" + audience + "/" + role + ".d"}
                   for role in ("providers", "consumers")}
        for audience in ("user", "system")}}


def isolate_xdg(env, home):
    home = Path(home)
    env.update({"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
                "XDG_DATA_HOME": str(home / ".local/share"),
                "XDG_STATE_HOME": str(home / ".local/state"),
                "XDG_CACHE_HOME": str(home / ".cache"),
                "XDG_CONFIG_DIRS": str(home / "site-config"),
                "XDG_DATA_DIRS": str(home / "vendor-data")})
    return env
