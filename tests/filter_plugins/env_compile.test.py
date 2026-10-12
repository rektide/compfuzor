#!/usr/bin/env python3
"""Explicit ENV normalization and non-executable assignment/projection grammar."""

import importlib.util
from pathlib import Path
import sys

from ansible.errors import AnsibleFilterError

sys.path.insert(0, "library/filter_plugins")
from env_compile import compile_env, values
from config_definitions import compile_definitions
from runtime_catalog import compile_runtime_catalog
from action_audiences import compile_action_audiences

module_spec = importlib.util.spec_from_file_location("env_processor", "files/config-env.py")
processor = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(processor)


def fails(callback, error_type):
    try:
        callback()
    except error_type:
        return
    raise AssertionError("expected rejection")


def test_env():
    special = "quote'\" dollar$ slash\\ snow☃"
    parsed = processor.assignments('EMPTY=\nSINGLE=\'literal $HOME\'\nDOUBLE="quote\\\" slash\\\\ snow☃"\nBARE=$(id)\n', "fixture")
    assert parsed == {"EMPTY": "", "SINGLE": "literal $HOME", "DOUBLE": 'quote" slash\\ snow☃', "BARE": "$(id)"}
    assert processor.serialize({"ODD": special}, "env") == 'ODD="quote\'\\" dollar$ slash\\\\ snow☃"\n'
    for text in ('BAD-NAME=x\n', 'export KEY=x\n', 'KEY="two\\nlines"\n', 'KEY="null\\u0000"\n', 'KEY=two words\n', 'KEY="unterminated\n'):
        fails(lambda: processor.assignments(text, "fixture"), ValueError)
    assert values({"lookup": True, "items": ["one", "two"]}, ["fallback"], {"lookup": "exact", "LOOKUP": "upper", "FALLBACK": "fallback"}) == {"FALLBACK": "fallback", "LOOKUP": "exact", "ITEMS": "one two"}
    fails(lambda: values({}, ["missing"], {}), AnsibleFilterError)
    fails(lambda: compile_env({"projections": {"../escape": {"files": [], "format": "env"}}}, {}, [], {}, [], {}, {}, "/fixture/etc", "/fixture"), AnsibleFilterError)
    assert compile_definitions({}, "/fixture/etc", "/fixture/bin", {})["instances"] == {}
    def definition(base, root):
        return {"etc": base, "configs": {"main.conf": {"processor": "concat", "inputs": [{"glob": "parts/*.conf", "name": "parts"}]}}, "contexts": {"user": {"scope": "user", "root": root}}}
    fails(lambda: compile_definitions({"a": definition("/fixture/etc/a", "/same"), "b": definition("/fixture/etc/b", "/same")}, "/fixture/etc", "/fixture/bin"), AnsibleFilterError)
    fails(lambda: compile_definitions({"sync": definition("/fixture/etc/sync", "/sync")}, "/fixture/etc", "/fixture/bin"), AnsibleFilterError)
    fails(lambda: compile_definitions({"foo": definition("/fixture/etc/foo", "/foo"), "foo-sync": definition("/fixture/etc/foo-sync", "/foo-sync")}, "/fixture/etc", "/fixture/bin"), AnsibleFilterError)
    definitions = {"a": definition("/fixture/etc/a", "/a"), "b": definition("/fixture/etc/b", "/b")}
    compiled = compile_definitions(definitions, "/fixture/etc", "/fixture/bin", defaults={"audiences": {"available": ["user"]}})
    actions = compile_action_audiences(compiled["contrib"]["BINS"], {"available": ["user"]})["spec"]["actions"]
    install = actions["install-config"]["plans"]["user"]
    assert {item["spec"] for item in install} == {"etc/config/a/spec.json", "etc/config/b/spec.json"}
    catalog = compile_runtime_catalog({"id": "deployment:fixture"}, compiled["contrib"]["BINS"], [], subsystems={"config": compiled}, etc_files=compiled["contrib"]["ETC_FILES"])
    assert {item["path"] for item in catalog["catalog"]["resources"] if item["contract"] == "compfuzor.config/v2"} == {"etc/config/a/spec.json", "etc/config/b/spec.json"}


if __name__ == "__main__":
    test_env()
    print("ok: ENV literal grammar, serializers, lookup precedence, invalid values, and CONFIG output conflicts")
