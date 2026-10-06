"""Controller-only audience/context mapping, independent of receiver placement."""
from collections.abc import Mapping
from ansible.errors import AnsibleFilterError
from action_audiences import AUDIENCES, mapping, policy_settings


def participating_audiences(policy, actions):
    base = policy_settings({key: value for key, value in policy.items() if key != "actions"}, "ACTION_AUDIENCES")
    result = set()
    for action in actions:
        value = policy.get("actions", {}).get(action, {})
        if value is not False:
            result.update(policy_settings(value, "ACTION_AUDIENCES.actions." + action, base)["available"])
    return result


def bind_action_contexts(contexts, explicit, label, eligible=AUDIENCES):
    explicit = mapping(explicit or {}, label)
    if set(explicit) - set(AUDIENCES):
        raise AnsibleFilterError(label + " keys must be user/system")
    result = {}
    for audience in eligible:
        name = explicit.get(audience)
        candidates = [key for key, value in contexts.items() if value.get("scope") == audience and not value.get("canonical")]
        if name is not None:
            if not isinstance(name, str) or name not in candidates:
                raise AnsibleFilterError("{} {} context {!r} must name a noncanonical {} receiver".format(label, audience, name, audience))
            result[audience] = name
        elif len(candidates) == 1:
            result[audience] = candidates[0]
        elif len(candidates) > 1:
            raise AnsibleFilterError("{}: ambiguous {} contexts {}; declare {}.{}".format(label, audience, ", ".join(candidates), label, audience))
    return result


class FilterModule:
    def filters(self):
        return {}
