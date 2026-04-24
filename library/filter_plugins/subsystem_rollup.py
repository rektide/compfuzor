from __future__ import absolute_import, division, print_function

__metaclass__ = type

from merge_strategy import merge_with_strategy


def subsystem_rollup(children, aggregate=None, include_aggregate=True):
    """Roll up child subsystem contrib payloads into one aggregate payload.

    Inputs:
    - children: list of subsystem state records or contrib dicts
      - if a child has a `contrib` key, that value is used
      - otherwise, the child itself is treated as contrib
    - aggregate: optional all/aggregate contrib payload to overlay last
    - include_aggregate: include `aggregate` payload when truthy

    Output keys:
    - ETC_FILES, BINS, ENV, ENV_LIST, PKGS
    """
    return merge_with_strategy(
        children,
        {
            "ETC_FILES": "append",
            "BINS": "append",
            "ENV": "dict_overlay",
            "ENV_LIST": "append_unique",
            "PKGS": "append_unique",
        },
        aggregate=aggregate,
        include_aggregate=include_aggregate,
        payload_key="contrib",
    )


class FilterModule(object):
    def filters(self):
        return {
            "subsystem_rollup": subsystem_rollup,
        }
