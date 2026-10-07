"""Thin named-resource packaging and shared keybinding installer synthesis."""
from __future__ import annotations
import collections.abc
import posixpath
import re
import shlex
from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers
from template_data import raw_copy_template_data
from config_selectors import compile_path_selector, relative_path
from config_context_compile import _root as context_root
from config_compile import config_runtime_bins, config_runtime_packages
from runtime_bundles import compfuzor_runtime_bins, runtime_alias_bin
from action_contexts import bind_action_contexts, participating_audiences
from registry_compile import registration_bins

ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
TARGETS = ("niri", "umbriel")

def fail(message):
    raise AnsibleFilterError("keybindings_compile: " + message)

def mapping(value, label):
    if value is None:
        return {}
    if not isinstance(value, collections.abc.Mapping):
        fail(label + " must be a mapping")
    return dict(value)

def identifier(value, label):
    if not isinstance(value, str) or not ID.fullmatch(value):
        fail(label + " must be a stable identifier")
    return value

def selector(value, label):
    return compile_path_selector(value, label)

def sequence(value, label):
    if not isinstance(value, list):
        fail(label + " must be a list")
    return value

def profile(target, raw, own_sources):
    raw = mapping(raw, target)
    unknown = set(raw) - {"contexts", "action_contexts", "root_file", "material_root", "membership", "placement", "placement_directory", "registration", "baseline", "personal", "user_sources", "native_sources", "bindings", "template_file"}
    if unknown:
        fail("unknown consumer settings: " + ", ".join(sorted(unknown)))
    contexts = {}
    for name, value in mapping(raw.get("contexts", {"user": {"scope": "user", "root": "config", "subpath": target}}), "contexts").items():
        identifier(name, "context")
        value = mapping(value, "context")
        if set(value) - {"scope", "root", "subpath"} or value.get("scope") not in ("user", "system"):
            fail("context requires scope user/system and CONFIG root conventions")
        contexts[name] = {"scope": value["scope"], "root": context_root(value.get("root", "config"), value["scope"], "keybinding context root")}
        if "subpath" in value:
            contexts[name]["subpath"] = relative_path(value["subpath"], "keybinding context subpath")
    result = {"version": 1, "target": target, "contexts": contexts, "placement": raw.get("placement", "link"), "registration": raw.get("registration", "link")}
    if result["placement"] not in ("direct", "copy", "link") or result["registration"] not in ("copy", "link"):
        fail("placement must be direct/copy/link; registration must be copy/link")
    for source, dest in [("root_file", "rootFile"), ("material_root", "materialRoot"), ("membership", "membership"), ("placement_directory", "placementDirectory"), ("template_file", "templateFile")]:
        if source in raw:
            result[dest] = selector(raw[source], source)
    for key in ("baseline", "personal"):
        defaults = ["/usr/local/share/umbriel/config.toml"] if key == "baseline" and target == "umbriel" else []
        result[key] = [selector(path, key) for path in sequence(raw.get(key, defaults), key)]
    result["userSources"] = list(own_sources)
    for value in sequence(raw.get("user_sources", []), "user_sources"):
        value = {"path": value} if isinstance(value, str) else mapping(value, "user source")
        if set(value) - {"path", "when_present", "disabled_suffix"}:
            fail("unknown user source settings")
        result["userSources"].append({"path": selector(value.get("path"), "user source"), **({"whenPresent": value["when_present"]} if "when_present" in value else {}), **({"disabledSuffix": value["disabled_suffix"]} if "disabled_suffix" in value else {})})
    result["nativeSources"] = []
    for value in sequence(raw.get("native_sources", []), "native_sources"):
        value = mapping(value, "native source")
        if set(value) - {"id", "path", "order", "placement", "incorporation", "enabled", "disabled_suffix"}:
            fail("unknown native source settings")
        placement = value.get("placement", "direct")
        placement = {"strategy": placement} if isinstance(placement, str) else mapping(placement, "native placement")
        strategy = placement.get("strategy")
        if strategy not in ("direct", "copy", "link"):
            fail("invalid native placement")
        output = {"id": identifier(value.get("id"), "native source id"), "path": selector(value.get("path"), "native source"), "format": target, "order": value.get("order", 10000), "placement": {"strategy": strategy}}
        if strategy != "direct":
            output["placement"]["path"] = selector(placement.get("path"), "native placement")
        for key in ("incorporation", "enabled"):
            if key in value:
                output[key] = value[key]
        if "disabled_suffix" in value:
            output["disabledSuffix"] = value["disabled_suffix"]
        result["nativeSources"].append(output)
    result["bindings"] = {}
    for name, value in mapping(raw.get("bindings"), "bindings policy").items():
        identifier(name, "binding id")
        value = mapping(value, "binding policy")
        if set(value) - {"order", "placement", "incorporation"}:
            fail("unknown binding policy fields")
        output = {key: setting for key, setting in value.items() if key != "placement"}
        if "placement" in value:
            placement = mapping(value["placement"], "binding placement")
            strategy = placement.get("strategy")
            if strategy not in ("direct", "copy", "link"):
                fail("invalid binding placement")
            output["placement"] = {"strategy": strategy}
            if strategy != "direct":
                output["placement"]["path"] = selector(placement.get("path"), "binding placement")
        result["bindings"][name] = output
    return result

@accept_args_markers
def compile_keybindings(actions, bindings, consumers, targets, producer, etc, bins_dir, order=100, context="user", scope="user", has_configs=False, audience_policy=None):
    actions = mapping(raw_copy_template_data(actions), "KEYBINDING_ACTIONS")
    bindings = mapping(raw_copy_template_data(bindings), "KEYBINDINGS")
    consumers = mapping(raw_copy_template_data(consumers), "KEYBINDING_CONSUMERS")
    targets = raw_copy_template_data(targets)
    identifier(producer, "producer")
    identifier(context, "context")
    if scope not in ("user", "system"):
        fail("scope must be user/system")
    files, resources, own_sources, bins, dirs = [], [], [], [], []
    for kind, declarations in [("action", actions), ("keybinding", bindings)]:
        for name in sorted(declarations):
            identifier(name, kind + " id")
            value = mapping(declarations[name], kind)
            for field, expected in [("id", name), ("kind", kind), ("version", 1)]:
                if field in value and value[field] != expected:
                    fail(field + " conflicts with the named declaration")
            document = {**value, "version": 1, "kind": kind, "id": name}
            path = kind + "/" + name + ".yaml"
            files.append({"name": path, "yaml": document})
            resources.append({"path": posixpath.join(etc, path)})
            own_sources.append({"path": {"path": posixpath.join(etc, path)}, "whenPresent": bool(value.get("patch", False))})
    profiles = {}
    advertisements = {}
    for target, value in consumers.items():
        identifier(target, "receiver id")
        value = mapping(value, "consumer")
        adapter = value.get("adapter", target)
        if adapter not in TARGETS:
            fail("consumer adapter must be niri/umbriel; arbitrary receiver ids require adapter")
        profile_settings = {key: item for key, item in value.items() if key not in ("adapter", "enabled", "profile_selector")}
        profiles[target] = profile(adapter, profile_settings, own_sources if targets is None else [])
        files.append({"name": "keybinding-" + target + ".json", "json": profiles[target]})
        for audience in ("user", "system"):
            contexts = [name for name, spec in profiles[target]["contexts"].items() if spec["scope"] == audience]
            if not contexts:
                continue
            owned = posixpath.join(etc, "keybinding-" + target + ".json")
            advertised = {"version": 1, "id": target, "adapter": adapter, "audience": audience,
                "profile": selector(value.get("profile_selector", owned), "owned profile selector"),
                "contexts": contexts, "defaultContext": value.get("action_contexts", {}).get(audience, contexts[0]), "enabled": value.get("enabled", True)}
            if advertised["defaultContext"] not in contexts:
                fail("advertised default context does not belong to audience")
            name = "keybindings/consumers/" + audience + "/" + target + ".json"
            files.append({"name": name, "json": advertised})
            advertisements[(target, audience)] = posixpath.join(etc, name)
            bins.extend(registration_bins("keybindings-consumer-" + target + "-" + audience, "keybinding-consumers", posixpath.join(etc, name), audience))
    target_map = {} if targets is None and consumers else {target: {} for target in TARGETS} if targets is None else {target: {} for target in targets} if isinstance(targets, list) else mapping(targets, "KEYBINDING_TARGETS")
    for target, value in target_map.items():
        identifier(target, "installer receiver")
        value = mapping(value, "target binding")
        if set(value) - {"consumer", "context", "scope", "action_contexts"}:
            fail("unknown target binding")
    # Role is declaration-driven, not inferred from current resource count.
    # Empty producer reinstalls must replace stale manifests/membership; only an
    # implicit consumer-only host omits the producer manifest.
    producer_role = targets is not None or not consumers
    if producer_role:
        files.append({"name": "keybinding-producer.json", "json": {"version": 1, "producer": producer, "order": order, "resources": resources, "targets": list(TARGETS) if target_map else []}})
        bins.extend(registration_bins("keybindings-provider", "keybinding-providers", posixpath.join(etc, "keybinding-producer.json"), scope))
        receivers = None if targets is None else []
        if receivers is not None:
            for receiver, settings in target_map.items():
                settings = mapping(settings, "receiver settings")
                item = {"id": receiver, **{key: settings[key] for key in ("context", "scope") if key in settings}}
                if settings.get("consumer"):
                    consumer = settings["consumer"]
                    if isinstance(consumer, str) and not consumer.endswith(".json"):
                        consumer = posixpath.join(consumer, "etc/keybinding-" + receiver + ".json")
                    item["profile"] = selector(consumer, "receiver override")
                receivers.append(item)
        selection_path = posixpath.join(etc, "keybindings/selection.json")
        files.append({"name": "keybindings/selection.json", "json": {"version": 1, "receivers": receivers}})
        generic = {"name": "install-keybindings.sh", "action": "install", "scope": [scope], "basedir": False, "deployment_rooted": True, "bypass": "KEYBINDINGS", "run": False,
            "content": 'exec "$DIR/bin/keybindings.mjs" install-offer --manifest ' + shlex.quote(posixpath.join(etc, "keybinding-producer.json")) + ' --selection ' + shlex.quote(selection_path) + ' --scope ' + scope + ' "$@"'}
        if audience_policy is not None:
            generic["compose"] = False
            delivery_scopes = {mapping(value, "target binding").get("scope", scope) for value in target_map.values()} or {scope}
            eligible = participating_audiences(audience_policy, ["install"]) & delivery_scopes
            generic["action_operations"] = [{"action": "install", "subsystem": "keybindings", "audiences": {audience: {"kind": "domain", "domain": "keybindings", "operation": "install-offer", "envelope": "bin/install-keybindings.sh", "manifest": posixpath.join(etc, "keybinding-producer.json"), "producer": producer, "selection": selection_path} for audience in eligible}}]
        bins.append(generic)
    # A domain host reuses STOCK CONFIG worker artifacts, without fabricating an
    # empty output recipe or auto-running installers during Ansible rendering.
    if not has_configs:
        bins.extend([{**value, "run": False} for value in config_runtime_bins()])
        bins.extend(compfuzor_runtime_bins("keybindings.mjs"))
        dirs.extend(posixpath.join(bins_dir, path) for path in ("config", "config/processors", "internal/config"))
    else:
        bins.append(runtime_alias_bin("keybindings.mjs"))
    for target in sorted(profiles):
        value = {}
        selected_context = value.get("context", context)
        identifier(selected_context, "target context")
        selected_scope = value.get("scope", scope)
        consumer = value.get("consumer")
        profile_path = None
        profile_selector = None
        if consumer:
            if isinstance(consumer, str):
                selected_path = consumer if consumer.endswith(".json") else posixpath.join(consumer, "etc/keybinding-" + target + ".json")
                compiled = compile_path_selector(selected_path, "consumer profile", allow_relative=False)
                if selected_path.startswith("/"):
                    profile_path = selected_path
                else:
                    profile_selector = compiled
            else:
                profile_selector = compile_path_selector(consumer, "consumer profile", allow_relative=False)
        elif target in profiles:
            profile_path = posixpath.join(etc, "keybinding-" + target + ".json")
            if selected_context not in profiles[target]["contexts"]:
                fail("unknown host context")
            selected_scope = profiles[target]["contexts"][selected_context]["scope"]
        if selected_scope not in ("user", "system"):
            fail("target scope must be user/system")
        installing = False
        adapter = profiles[target]["target"]
        args = ["host", "--target", adapter, "--context", selected_context, "--scope", selected_scope]
        args.extend(["--descriptor", advertisements[(target, selected_scope)]])
        if installing:
            args.extend(["--manifest", posixpath.join(etc, "keybinding-producer.json")])
        descriptor = {"name": "install-keybindings-" + target + ".sh", "action": "install", "scope": [selected_scope], "basedir": False, "deployment_rooted": True, "bypass": "KEYBINDINGS", "run": False, "content": 'exec "$DIR/bin/keybindings.mjs" ' + " ".join(shlex.quote(arg) for arg in args) + ' "$@"'}
        if audience_policy is not None:
            descriptor["compose"] = False
            public_actions = ["install"] + (["assemble"] if target in profiles else [])
            eligible = participating_audiences(audience_policy, public_actions)
            explicit = value.get("action_contexts", consumers.get(target, {}).get("action_contexts"))
            if consumer:
                audience_contexts = mapping(explicit, "KEYBINDING_TARGETS." + target + ".action_contexts") if explicit is not None else {selected_scope: selected_context}
                if set(audience_contexts) - {"user", "system"}:
                    fail("action_contexts keys must be user/system")
                audience_contexts = {audience: identifier(name, "action context") for audience, name in audience_contexts.items() if audience in eligible}
            elif target in profiles:
                audience_contexts = bind_action_contexts(profiles[target]["contexts"], explicit, "KEYBINDING_CONSUMERS." + target + ".action_contexts", eligible)
            else:
                audience_contexts = {selected_scope: selected_context} if selected_scope in eligible else {}
            descriptor["action_operations"] = []
            owned_mapping = consumers.get(target, {}).get("action_contexts")
            if owned_mapping is None and not consumer:
                owned_mapping = value.get("action_contexts")
            for public_action in public_actions:
                operation = "install" if installing and public_action == "install" else "host"
                selected_bindings = audience_contexts
                common = {"kind": "domain", "domain": "keybindings", "operation": operation, "target": adapter,
                    "envelope": "bin/" + descriptor["name"], **({"mode": "assemble"} if public_action == "assemble" else {})}
                if operation == "install":
                    common.update({"manifest": posixpath.join(etc, "keybinding-producer.json"), "producer": producer})
                if public_action == "assemble":
                    selected_bindings = bind_action_contexts(profiles[target]["contexts"], owned_mapping, "KEYBINDING_CONSUMERS." + target + ".action_contexts", eligible)
                descriptor["action_operations"].append({"action": public_action, "subsystem": "keybindings-" + target,
                    "audiences": {audience: {**common, "context": name, "descriptor": advertisements[(target, audience)]} for audience, name in selected_bindings.items()}})
            if installing and target in profiles:
                owned_path = posixpath.join(etc, "keybinding-" + target + ".json")
                host_bindings = bind_action_contexts(profiles[target]["contexts"], owned_mapping, "KEYBINDING_CONSUMERS." + target + ".action_contexts", eligible)
                distinct = {audience: name for audience, name in host_bindings.items() if profile_path != owned_path or audience_contexts.get(audience) != name}
                if distinct:
                    descriptor["action_operations"].insert(0, {"action": "install", "subsystem": "keybindings-" + target,
                        "audiences": {audience: {"kind": "domain", "domain": "keybindings", "operation": "host", "target": target, "envelope": "bin/" + descriptor["name"], "context": name, "profile": owned_path} for audience, name in distinct.items()}})
        bins.append(descriptor)
    return {"files": files, "bins": bins, "dirs": dirs, "pkgs": config_runtime_packages()}

class FilterModule(object):
    def filters(self):
        return {"keybindings_compile": compile_keybindings}
