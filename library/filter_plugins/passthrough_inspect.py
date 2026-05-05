from ansible.template import accept_args_markers


@accept_args_markers
def passthrough_inspect(value):
    print("=== FILTER INSPECT ===")
    print("  type: {}".format(type(value).__name__))
    if isinstance(value, dict):
        for k, v in value.items():
            print("  key={}, val_type={}, val_repr={}".format(k, type(v).__name__, repr(v)[:120]))
    elif isinstance(value, str):
        print("  repr: {}".format(repr(value)[:200]))
    else:
        print("  value: {}".format(repr(value)[:200]))
    print("=== END INSPECT ===")
    return value


@accept_args_markers
def materialize_dict(value):
    print("=== MATERIALIZE ===")
    print("  input type: {}".format(type(value).__name__))
    result = {}
    if isinstance(value, dict):
        for k, v in value.items():
            v_type = type(v).__name__
            print("  key={}, val_type={}".format(k, v_type))
            if v_type == '_AnsibleTaggedStr':
                result[k] = str(v)
            else:
                result[k] = v
    print("  output type: {}".format(type(result).__name__))
    print("=== END MATERIALIZE ===")
    return result


@accept_args_markers
def count_templates(value):
    count = 0
    if isinstance(value, dict):
        print("  dict type: {}".format(type(value).__name__))
        print("  dict keys: {}".format(list(value.keys())))
        try:
            items = list(value.items())
            print("  items() succeeded, len={}".format(len(items)))
        except Exception as e:
            print("  items() FAILED: {}".format(e))
            return -1
        for k, v in items:
            try:
                v_type = type(v).__name__
                print("  key={}, type_check OK: {}".format(k, v_type))
            except Exception as e:
                print("  key={}, type_check FAILED: {}".format(k, e))
                continue
            try:
                v_repr = repr(v)
                print("  key={}, repr OK: {}".format(k, v_repr[:120]))
            except Exception as e:
                print("  key={}, repr FAILED: {}".format(k, e))
                continue
            try:
                has_braces = '{{' in v_repr
                if v_type == '_AnsibleTaggedStr' and has_braces:
                    count += 1
            except Exception as e:
                print("  key={}, brace_check FAILED: {}".format(k, e))
    return count


@accept_args_markers
def merge_preserving(value, patch):
    print("=== MERGE PRESERVING ===")
    print("  value type: {}".format(type(value).__name__))
    print("  patch type: {}".format(type(patch).__name__))
    if isinstance(value, dict) and isinstance(patch, dict):
        for k, v in value.items():
            print("  src key={}, val_type={}, repr={}".format(k, type(v).__name__, repr(v)[:80]))
        for k, v in patch.items():
            print("  patch key={}, val_type={}, repr={}".format(k, type(v).__name__, repr(v)[:80]))
        result = dict(value)
        result.update(patch)
        print("  result keys: {}".format(list(result.keys())))
        print("=== END MERGE ===")
        return result
    print("  not dicts, returning value")
    print("=== END MERGE ===")
    return value


class FilterModule(object):
    def filters(self):
        return {
            "passthrough_inspect": passthrough_inspect,
            "materialize_dict": materialize_dict,
            "count_templates": count_templates,
            "merge_preserving": merge_preserving,
        }
