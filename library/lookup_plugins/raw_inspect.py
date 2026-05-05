from ansible.plugins.lookup import LookupBase


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        var_name = terms[0] if terms else None
        if not var_name:
            return [None]

        print("=== LOOKUP INSPECT ===")
        val = variables.get(var_name) if variables else None
        if val is None:
            print("  not found")
            return [None]

        print("  type: {}".format(type(val).__name__))
        if isinstance(val, dict):
            for k, v in val.items():
                print("  key={}, val_type={}, val_repr={}".format(k, type(v).__name__, repr(v)[:120]))
        print("=== END LOOKUP ===")
        return [val]
