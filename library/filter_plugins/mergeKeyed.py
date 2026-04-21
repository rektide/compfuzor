from subsystem_fields import merge_with_strategy


def mergeKeyed(list1, list2, key="key", concat_fields=None):
    """Compatibility shim implemented via merge_with_strategy."""
    merged = merge_with_strategy(
        [{"items": list1}, {"items": list2}],
        {
            "items": {
                "op": "merge_keyed",
                "key": key,
                "concat_fields": concat_fields,
            }
        },
        include_aggregate=False,
    )
    return merged.get("items", [])


class FilterModule(object):
    def filters(self):
        return {"mergeKeyed": mergeKeyed}
