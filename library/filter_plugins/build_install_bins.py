from __future__ import absolute_import, division, print_function

__metaclass__ = type


def build_install_bins(stem, basedir=False, src_root="../kernel"):
    """Return standard build/install bin entries for a stem.

    Example:
    - stem: "sysctl"
      -> build-sysctl.sh / install-sysctl.sh
    - stem: "kernel"
      -> build-kernel.sh / install-kernel.sh
    """
    stem_text = str(stem).strip()
    if not stem_text:
        return {"build_bins": [], "install_bins": []}

    return {
        "build_bins": [
            {
                "name": "build-{}.sh".format(stem_text),
                "src": "{}/build-{}.sh".format(src_root, stem_text),
                "basedir": basedir,
            }
        ],
        "install_bins": [
            {
                "name": "install-{}.sh".format(stem_text),
                "src": "{}/install-{}.sh".format(src_root, stem_text),
                "basedir": basedir,
            }
        ],
    }


class FilterModule(object):
    def filters(self):
        return {
            "build_install_bins": build_install_bins,
        }
