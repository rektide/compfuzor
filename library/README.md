# Ansible Plugin Reference

`/library` contains custom Ansible plugins used by Compfuzor.

## Tests

Tests are used with `is` in Jinja/Ansible conditionals.

| Name | Source | Behavior |
| --- | --- | --- |
| `deftruthy` | [`library/test_plugins/deftruthy.py`](/library/test_plugins/deftruthy.py) | True if value is defined and truthy. |
| `deffalsy` | [`library/test_plugins/deftruthy.py`](/library/test_plugins/deftruthy.py) | True if value is undefined or falsy. |
| `having` | [`library/test_plugins/havingattr.py`](/library/test_plugins/havingattr.py) | True if dict has all requested attributes with truthy values. |
| `havingattr` | [`library/test_plugins/havingattr.py`](/library/test_plugins/havingattr.py) | Alias of `having`. |
| `havingany` | [`library/test_plugins/havingattr.py`](/library/test_plugins/havingattr.py) | True if dict has any requested attribute with a truthy value. |

### Example

```yaml
when: MY_FLAG is deftruthy
when: MY_BYPASS is deffalsy
when: my_dict is having('foo', 'bar')
```

## Filters

Filters transform values using `|` in Jinja templates.

| Name | Source | Behavior |
| --- | --- | --- |
| `arrayitize` | [`library/filter_plugins/arrayitize.py`](/library/filter_plugins/arrayitize.py) | Normalizes arguments into a list and flattens list-like inputs. |
| `should_become` | [`library/filter_plugins/can_write.py`](/library/filter_plugins/can_write.py) | Heuristic for when privilege escalation may be needed (ownership/write checks). |
| `has_write` | [`library/filter_plugins/can_write.py`](/library/filter_plugins/can_write.py) | Checks write access for a path (controller-side filesystem check). |
| `can_write` | [`library/filter_plugins/can_write.py`](/library/filter_plugins/can_write.py) | Checks writeability, walking to parent directories for missing paths. |
| `diff_user` | [`library/filter_plugins/can_write.py`](/library/filter_plugins/can_write.py) | Compares requested and current user/group identity values. |
| `to_uid` | [`library/filter_plugins/can_write.py`](/library/filter_plugins/can_write.py) | Converts username or numeric input to a UID-like value. |
| `to_gid` | [`library/filter_plugins/can_write.py`](/library/filter_plugins/can_write.py) | Converts group name or numeric input to a GID-like value. |
| `ansible_cmdline` | [`library/filter_plugins/cmdline.py`](/library/filter_plugins/cmdline.py) | Parses cmdline text and extracts `<type>.<instance>.pb` into `{type, instance}`. |
| `def` | [`library/filter_plugins/def.py`](/library/filter_plugins/def.py) | Returns value unless undefined; optional fallback arg; else `None`. |
| `truthy` | [`library/filter_plugins/def.py`](/library/filter_plugins/def.py) | Boolean coercion that treats undefined as `False` (or fallback arg). |
| `defaultDir` | [`library/filter_plugins/defaultDir.py`](/library/filter_plugins/defaultDir.py) | Prefixes relative paths with a default directory; leaves absolute/home paths unchanged. |
| `deprefix` | [`library/filter_plugins/deprefix.py`](/library/filter_plugins/deprefix.py) | Removes a regex prefix from the start of a string/path. |
| `depostfix` | [`library/filter_plugins/deprefix.py`](/library/filter_plugins/deprefix.py) | Trims using a regex postfix-style match at the end of a string/path. |
| `deregex` | [`library/filter_plugins/deprefix.py`](/library/filter_plugins/deprefix.py) | Returns the substring matched by a regex. |
| `ignore_empty` | [`library/filter_plugins/ignore_empty.py`](/library/filter_plugins/ignore_empty.py) | Removes dict entries whose value is `None` or empty string. |
| `listify` | [`library/filter_plugins/listify.py`](/library/filter_plugins/listify.py) | Converts input to list form (`dict` -> list of `{key, value}`). |
| `concat` | [`library/filter_plugins/listify.py`](/library/filter_plugins/listify.py) | Concatenates arguments after `listify` conversion. |
| `mergeKeyed` | [`library/filter_plugins/mergeKeyed.py`](/library/filter_plugins/mergeKeyed.py) | Merges two lists of objects by key, with optional concat fields. |
| `rejectAny` | [`library/filter_plugins/rejectAny.py`](/library/filter_plugins/rejectAny.py) | Returns elements from first iterable not present in second iterable. |
| `unsafety` | [`library/filter_plugins/unsafety.py`](/library/filter_plugins/unsafety.py) | Marks a value as trusted template content. |
| `has_var` | [`library/filter_plugins/vars.py`](/library/filter_plugins/vars.py) | Looks up one or more variable names in `vars`/`hostvars`. |
| `has_vars` | [`library/filter_plugins/vars.py`](/library/filter_plugins/vars.py) | Alias of `has_var`. |
