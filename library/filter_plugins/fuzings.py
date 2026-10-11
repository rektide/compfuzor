"""Compile explicit deployment-local fuze/fuzing declarations; never enroll or run."""

from collections.abc import Mapping
import posixpath
import re

from ansible.errors import AnsibleFilterError


_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_KINDS = ("zim-import", "shell-source", "exec")


def _fail(message):
    raise AnsibleFilterError("fuzings: " + message)


def _record(value, keys, label):
    if not isinstance(value, Mapping):
        _fail(label + " must be a mapping")
    unknown = set(value) - set(keys)
    if unknown:
        _fail(label + " has unknown fields: " + ", ".join(sorted(unknown)))
    return value


def _name(value, label):
    if not isinstance(value, str) or not _NAME.fullmatch(value):
        _fail("invalid " + label)
    return value


def _directory(value, label):
    if not isinstance(value, str) or not value.startswith("/") or "\0" in value:
        _fail(label + " must be an absolute directory")
    if value == "/" or posixpath.normpath(value) != value or value.startswith("//"):
        _fail(label + " must be a normalized non-root directory")
    return value


def _scope(value):
    if value not in ("user", "system"):
        _fail("scope must be user or system")
    return value


def _kind(value):
    if value not in _KINDS:
        _fail("kind must be zim-import, shell-source, or exec")
    return value


def _path(value, kind):
    prefix = "bin/" if kind == "exec" else "etc/"
    if (not isinstance(value, str) or not value.startswith(prefix) or "\0" in value
            or any(part in ("", ".", "..") for part in value.split("/"))):
        _fail(kind + " path must be a relative file beneath " + prefix)
    return value


def compile_fuzings(fuze, fuzings, name, directory):
    """Inputs must be resolved at task scope, like ZIM_ENV projections."""
    deployment = {"id": _name(name, "deployment ID"), "dir": _directory(directory, "deployment dir")}
    files, dirs = [], []
    if fuze is not None:
        raw = _record(fuze, ("id", "scope", "actions"), "FUZE")
        actions = raw.get("actions")
        if not isinstance(actions, Mapping) or not actions:
            _fail("FUZE.actions must be a nonempty mapping")
        compiled = {}
        for action, value in actions.items():
            _name(action, "action name")
            value = _record(value, ("kind", "required"), "FUZE action " + action)
            required = value.get("required", [])
            if not isinstance(required, list):
                _fail("required must be a list of fuzing IDs")
            required = [_name(item, "required fuzing ID") for item in required]
            if len(set(required)) != len(required):
                _fail("duplicate required fuzing ID")
            compiled[action] = {"kind": _kind(value.get("kind")), "required": required}
        files.append({"name": "fuze.json", "json": {
            "version": 1, "id": _name(raw.get("id"), "fuze ID"),
            "deployment": deployment, "scope": _scope(raw.get("scope")), "actions": compiled,
        }})
        dirs.append("fuze.d")
    if fuzings is not None:
        if not isinstance(fuzings, list):
            _fail("FUZINGS must be a list")
        ids, sources = set(), []
        for value in fuzings:
            raw = _record(value, ("id", "target", "actions"), "fuzing")
            identity = _name(raw.get("id"), "fuzing ID")
            if identity in ids:
                _fail("duplicate fuzing ID: " + identity)
            ids.add(identity)
            target = _record(raw.get("target"), ("dir", "fuze", "scope"), "target")
            target = {"dir": _directory(target.get("dir"), "target dir"),
                      "fuze": _name(target.get("fuze"), "target fuze"),
                      "scope": _scope(target.get("scope"))}
            actions = raw.get("actions")
            if not isinstance(actions, Mapping) or not actions:
                _fail("fuzing actions must be a nonempty mapping")
            compiled = {}
            for action, entry in actions.items():
                _name(action, "action name")
                entry = _record(entry, ("kind", "order", "path", "args"), "fuzing action " + action)
                kind, order = _kind(entry.get("kind")), entry.get("order")
                if not isinstance(order, int) or isinstance(order, bool) or not 0 <= order <= 9007199254740991:
                    _fail("order must be a nonnegative safe integer")
                result = {"kind": kind, "order": order}
                if kind != "zim-import":
                    result["path"] = _path(entry.get("path"), kind)
                elif "path" in entry:
                    _fail("zim-import does not accept path")
                if kind == "exec":
                    args = entry.get("args", [])
                    if not isinstance(args, list) or any(not isinstance(arg, str) or "\0" in arg for arg in args):
                        _fail("args must be a list of literal strings without NUL")
                    result["args"] = args
                elif "args" in entry:
                    _fail(kind + " does not accept args")
                compiled[action] = result
            source = "fuzings/" + identity + ".json"
            sources.append(source)
            files.append({"name": source, "json": {
                "version": 1, "id": identity, "deployment": deployment,
                "target": target, "actions": compiled,
            }})
        dirs.append("fuzings")
        files.append({"name": "fuzings.json", "json": {
            "version": 1, "deployment": deployment, "sources": sources,
        }})
    return {"etc_files": files, "etc_dirs": dirs}


class FilterModule:
    def filters(self):
        return {"fuzings_compile": compile_fuzings}
