"""His web's layout, for the reel's 3D web (insta_scene.py) and its sounds (insta_make.py): no Blender here.

The game's own layout (WebLayout in lib/screens/web_screen.dart): the first set in the middle, each step out
a ring, each branch its own slice of the circle, wider the more lies in it. And the order and moments in
which the knots come in: ring by ring, around each ring in turn.
"""
import math


def layout(nodes):
    children = {}
    for n in nodes:
        if n["parent"]:
            children.setdefault(n["parent"], []).append(n["id"])
    memo = {}

    def leaves(i):
        if i not in memo:
            kids = children.get(i, [])
            memo[i] = 1 if not kids else sum(leaves(k) for k in kids)
        return memo[i]

    share = lambda i: 1 + 0.6 * (leaves(i) - 1)
    angle, depth, branch = {"seed": 0.0}, {"seed": 0}, {"seed": 0}

    def cut(i, a0, a1, d):
        kids = children.get(i, [])
        total = sum(share(k) for k in kids) or 1
        a = a0
        for n, k in enumerate(kids):
            width = (a1 - a0) * share(k) / total
            angle[k], depth[k] = a + width / 2, d
            branch[k] = n if d == 1 else branch[i]
            cut(k, a, a + width, d + 1)
            a += width

    cut("seed", -math.pi / 2, 3 * math.pi / 2, 1)
    return angle, depth, branch


def appear_times(nodes, t0, t1):
    """When each knot comes in, between t0 and t1."""
    angle, depth, _ = layout(nodes)
    order = sorted([n["id"] for n in nodes if n["id"] != "seed"], key=lambda i: (depth[i], angle[i]))
    out = {"seed": t0}
    span = t1 - t0
    for k, i in enumerate(order):
        out[i] = t0 + 0.35 + (span - 0.6) * k / max(1, len(order) - 1)
    return out
