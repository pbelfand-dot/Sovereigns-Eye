"""Lays out the churchyard sets for data/props.json ("sets": churchyard_0..3,
churchyard_small_0..3), one per charter and yard size.

    python3 make_sets.py            # prints the "sets" lines
    python3 make_sets.py --write    # writes them into data/props.json

The set's frame is the yard's: +X across, +Z east (away from the chapel),
metres; the yard is 9.2 x 9.2 m (small: 9.2 x 5.2), centred on the origin.
Graves lie east-west, head to the west (-Z) where the cross stands. The
gateway is on the west side, toward the chapel. Walls run between ashlar
piers on 2 m pieces; fences are 2 m hurdles or paled lengths from the
Farm & Field family, laid to meet exactly at the corners.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROPS = os.path.join(HERE, "..", "..", "..", "..", "data", "props.json")

HALF_X = 4.6
HALF_Z = {"full": 4.6, "small": 2.6}


def C(name):
    return "chapel:" + name


def item(model, x, z, yaw=0):
    return [model, round(x, 2) + 0.0, 0, round(z, 2) + 0.0, yaw]


def walls(kind, d):
    """Piers at the corners, 2 m lengths between them, and the west side's
    gateway (2.8 m) between two more piers. `kind`: rubble or coped."""
    wall = C("SE_Wall_Rubble" if kind == "rubble" else "SE_Wall_Coped")
    line_x, line_z = HALF_X - 0.3, d - 0.3
    out = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            out.append(item(C("SE_Wall_Pier"), sx * line_x, sz * line_z))
    n_far = int(round((2 * line_x - 0.6) / 2))
    for i in range(n_far):   # east side
        out.append(item(wall, -line_x + 0.3 + 1 + 2 * i, line_z, 0))
    n_side = int(round((2 * line_z - 0.6) / 2))
    for sx in (-1, 1):       # the two long sides
        for i in range(n_side):
            out.append(item(wall, sx * line_x, -line_z + 0.3 + 1 + 2 * i, 90))
    for sx in (-1, 1):       # west side: a length each side of the gateway's piers
        out.append(item(wall, sx * (line_x - 0.3 - 1), -line_z, 0))
        out.append(item(C("SE_Wall_Pier"), sx * 1.7, -line_z))
    return out


def fences(kind, d):
    """Hurdles (Hamlet) or paled lengths (Village) on lines 0.6 m in from the
    yard's edge, 2 m each, meeting at the corners; on the west side two
    lengths, the gate, one more. The good side faces out."""
    piece = "farm:SE_Fence_Wattle" if kind == "wattle" else "farm:SE_Fence_Paled"
    gate = "farm:SE_Gate_Wattle" if kind == "wattle" else "farm:SE_Gate_Rail"
    x, z = HALF_X - 0.6, d - 0.6
    out = []
    # A piece's origin is one end; it runs 2 m along its own +X.
    for i in range(int(round(2 * x / 2))):      # east side, facing east (+Z)
        out.append(item(piece, -x + 2 * i, z, 0))
    for i in range(int(round(2 * z / 2))):      # the +X side, facing +X: runs toward -Z
        out.append(item(piece, x, z - 2 * i, 90))
    for i in range(int(round(2 * z / 2))):      # the -X side, facing -X: runs toward +Z
        out.append(item(piece, -x, -z + 2 * i, -90))
    # West side facing west (-Z): a piece at origin x0 runs toward -X.
    out.append(item(piece, -x + 2, -z, 180))     # -4 .. -2
    out.append(item(piece, -x + 4, -z, 180))     # -2 .. 0
    out.append(item(gate, 0.0, -z, 0))           # the gate, 0 .. 2
    out.append(item(piece, x, -z, 180))          # 2 .. 4
    return out


def grave(kind, x, z, marker=True):
    """A grave centred at (x, z): its cover and, at its head (-Z), a cross."""
    out = [item(C({"mound": "SE_Grave_Mound", "fresh": "SE_Grave_Fresh", "slab": "SE_Grave_Slab", "knight": "SE_Grave_Slab_Knight"}[kind]), x, z)]
    if marker and kind in ("mound", "fresh"):
        out.append(item(C("SE_Grave_Cross"), x + 0.02, z - (1.16 if kind == "fresh" else 1.08), 0))
    return out


# Each charter's churchyard: what stands in it. Full yards hold two rows
# of graves either side of the path from the gateway; the churchyard cross
# stands at the path's end (Village and up), the yew in a corner at the
# east end (Village and up), the lychgate in the gateway (Town). A shallow
# yard has one row, its cross to one side and no yew.
GRAVES_FULL = {
    0: [("mound", -3.2, -1.3), ("mound", -2.1, -1.3), ("fresh", 2.1, -1.3), ("mound", 3.2, 1.7), ("mound", 2.1, 1.7, False)],
    1: [("mound", -3.2, -1.3), ("mound", -2.1, -1.3), ("mound", 2.1, -1.3), ("fresh", 3.2, -1.3), ("mound", 2.1, 1.8), ("mound", 3.2, 1.8, False)],
    2: [("mound", -3.2, -1.3), ("slab", -2.1, -1.3), ("mound", 2.1, -1.3), ("mound", 3.2, -1.3, False), ("slab", 2.1, 1.8), ("fresh", 3.2, 1.8)],
    3: [("slab", -3.2, -1.3), ("mound", -2.1, -1.3), ("mound", 2.1, -1.25), ("fresh", 3.2, -1.3), ("knight", 2.1, 1.8), ("slab", 3.2, 1.8)],
}
GRAVES_SMALL = {
    0: [("mound", -3.2, 0.2), ("mound", -2.1, 0.2), ("fresh", 2.1, 0.2)],
    1: [("mound", -3.2, 0.2), ("mound", -2.1, 0.2), ("fresh", 0.4, 0.2)],
    2: [("mound", -3.2, 0.2), ("slab", -2.1, 0.2), ("mound", 0.4, 0.2)],
    3: [("slab", -3.2, 0.2), ("mound", -2.1, 0.2)],
}


def churchyard(charter, size):
    d = HALF_Z[size]
    out = []
    if charter == 0:
        out += fences("wattle", d)
    elif charter == 1:
        out += fences("paled", d)
    else:
        out += walls("rubble" if charter == 2 else "coped", d)
    if charter == 3:
        out.append(item(C("SE_Lychgate"), 0.0, -d + 1.5, 180))
    if size == "full":
        if charter >= 1:
            out.append(item(C("SE_Churchyard_Cross"), 0.0, 2.0, 0))
            out.append(item(C("SE_Yew"), -2.9, 2.6, 30))
        for g in GRAVES_FULL[charter]:
            out += grave(g[0], g[1], g[2], g[3] if len(g) > 3 else True)
    else:
        if charter >= 1:
            out.append(item(C("SE_Churchyard_Cross"), 2.6, 0.6, 0))
        for g in GRAVES_SMALL[charter]:
            out += grave(g[0], g[1], g[2], g[3] if len(g) > 3 else True)
    return out


def lines():
    out = []
    for size, prefix in (("full", "churchyard"), ("small", "churchyard_small")):
        for charter in range(4):
            items = churchyard(charter, size)
            text = json.dumps(items, separators=(", ", ": "))
            # Wrap after every few items, the way the file's other sets are.
            parts = re.split(r"(?<=\]), (?=\[)", text[1:-1])
            rows = [", ".join(parts[i:i + 5]) for i in range(0, len(parts), 5)]
            body = (",\n      ").join(rows)
            out.append('    "%s_%d": [%s]' % (prefix, charter, body))
    return out


def main():
    text = ",\n".join(lines())
    if "--write" not in sys.argv:
        print(text)
        return
    src = open(PROPS).read()
    # Replace the old churchyard sets if there are any, else add them after the training yards.
    src = re.sub(r'    "churchyard(_small)?_\d": \[.*?\]\],?\n', "", src, flags=re.S)
    anchor = re.search(r'    "training_small_3": \[.*?\]\],\n', src, flags=re.S)
    src = src[:anchor.end()] + text + ",\n" + src[anchor.end():]
    open(PROPS, "w").write(src)
    json.loads(src)
    print("wrote", PROPS)


if __name__ == "__main__":
    main()
