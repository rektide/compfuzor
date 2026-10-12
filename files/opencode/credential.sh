# Persistent account credential, distinct from systemd's ephemeral copy.
# Run as the owning account. Ensure never rotates an existing credential;
# status is read-only. No credential values cross stdout or shell variables.
exec python3 - "{{PASSWORDS_DIR}}/OPENCODE_PASSWORD" "$@" <<'PY'
import os
from pathlib import Path
import secrets
import stat
import sys
import tempfile

path = Path(sys.argv[1])
args = sys.argv[2:]
if args in (["--help"], ["-h"]):
    print("usage: credential.sh [ensure|status]\nRun as the service account. Ensure creates or secures its source without rotation.")
    raise SystemExit(0)
if len(args) > 1 or (args and args[0] not in ("ensure", "status")):
    raise SystemExit("usage: credential.sh [ensure|status]")
ensure = not args or args[0] == "ensure"
uid = os.getuid()
if ensure:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
directory = path.parent.lstat()
if not stat.S_ISDIR(directory.st_mode) or directory.st_uid != uid:
    raise SystemExit("credential: secrets directory must be a directory owned by the invoking account")
if ensure:
    path.parent.chmod(0o700)
elif stat.S_IMODE(directory.st_mode) != 0o700:
    raise SystemExit("credential: secrets directory must have mode 0700; run credential.sh ensure")

if ensure and not os.path.lexists(path):
    # Publish a fully written source without replacing another ensure's result.
    fd, temporary = tempfile.mkstemp(prefix=".credential-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write((secrets.token_urlsafe(32) + "\n").encode())
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, path)
        except FileExistsError:
            pass
    finally:
        os.unlink(temporary)

fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
with os.fdopen(fd, "rb") as stream:
    info = os.fstat(stream.fileno())
    if not stat.S_ISREG(info.st_mode) or info.st_uid != uid:
        raise SystemExit("credential: source must be a regular file owned by the invoking account")
    if info.st_size > 65536:
        raise SystemExit("credential: source is unexpectedly large")
    value = stream.read(65537).rstrip(b"\r\n")
    if not value or b"\n" in value or b"\r" in value or b"\x00" in value:
        raise SystemExit("credential: source must contain one nonempty password line")
    if ensure:
        os.fchmod(stream.fileno(), 0o600)
    elif stat.S_IMODE(info.st_mode) != 0o600:
        raise SystemExit("credential: source must have mode 0600; run credential.sh ensure")
print(f"credential: ready: {path} (uid {uid}, mode 0600)")
PY
