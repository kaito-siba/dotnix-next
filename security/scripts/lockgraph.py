"""flake.lock as a graph: every reachable node by its input path.

`nix flake update` can move a transitive input (herdr/rust-overlay, ...)
without touching any direct one, so a check that only looks at the root's
inputs misses it. Walking from the root and keying nodes by their path
("herdr/rust-overlay") makes the comparison independent of the node names
nix generates (nixpkgs_2 and friends).
"""
import json


def load(path):
    with open(path) as f:
        return json.load(f)


def resolve(lock, ref):
    """A node reference is a node name or, for `follows`, a path from root."""
    if isinstance(ref, str):
        return ref
    name = lock["root"]
    for step in ref:
        name = lock["nodes"][name]["inputs"][step]
        if isinstance(name, list):  # follows of a follows
            name = resolve(lock, name)
    return name


def walk(lock):
    """{ "a/b/c": node } for every node reachable from the root. Inputs that
    `follows` another path are listed under the followed path only."""
    out = {}
    seen = set()

    def visit(name, path):
        if name in seen:
            return
        seen.add(name)
        node = lock["nodes"][name]
        if path:
            out[path] = node
        for child, ref in (node.get("inputs") or {}).items():
            if isinstance(ref, list):
                continue  # a follows; the target is reached through its own path
            visit(ref, f"{path}/{child}" if path else child)

    visit(lock["root"], "")
    return out


def identity(node):
    """What makes a locked input the same input: where it comes from and
    which content. narHash covers tarballs without a rev."""
    locked = node.get("locked") or {}
    return (
        locked.get("type"),
        locked.get("owner"),
        locked.get("repo"),
        locked.get("url"),
        locked.get("rev"),
        locked.get("narHash"),
    )


def changed(old, new):
    """Paths whose locked identity differs (or that are new), from two lock
    graphs as returned by walk()."""
    return sorted(p for p, node in new.items() if p not in old or identity(old[p]) != identity(node))
