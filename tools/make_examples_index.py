#!/usr/bin/env python3
"""Writes examples/index.json (the list of examples the viewer offers) from the file names in examples/.
File names: <collective>_<flat|hier>_<N>loc_<M>nodes.csv; everything else is listed under "Other"."""
import glob
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
EX = os.path.join(HERE, "..", "examples")
INFO = [
    ("bcast", "Broadcast", "One locality sends data to all others. Flat: the root answers every request one by one; tree: every node asks its parent."),
    ("reduce", "Reduce", "All localities combine a value at the root."),
    ("allreduce", "All-reduce", "Combine a value and give the result to everybody. In the tree variant HPX reduces up the tree and broadcasts the result down."),
    ("gather", "Gather", "The root collects one block from every locality."),
    ("allgather", "All-gather", "Everybody gets all blocks. In the tree variant HPX gathers up and broadcasts down."),
    ("scatter", "Scatter", "The root sends a different block to every locality."),
    ("alltoall", "All-to-all", "Every locality sends a small value to every other one. In the tree variant HPX also uses gather and scatter."),
    ("alltoall_large", "All-to-all, large messages", "The same with 8 KiB per pair."),
    ("scan_ex", "Exclusive scan", "Prefix sum over the localities, without the own value. In the tree variant HPX uses gather and scatter."),
    ("scan_in", "Inclusive scan", "Prefix sum over the localities, with the own value. In the tree variant HPX uses gather and scatter."),
    ("barrier", "Barrier", "All localities wait for each other."),
]
pat = re.compile(r"^(?P<c>[a-z_]+?)_(?P<k>flat|hier)_(?P<l>\d+)loc_(?P<n>\d+)nodes\.csv$")
found, other = {}, []
for path in sorted(glob.glob(os.path.join(EX, "*.csv"))):
    name = os.path.basename(path)
    m = pat.match(name)
    if m:
        found.setdefault(m["c"], []).append({"file": name, "kind": m["k"], "localities": int(m["l"]), "nodes": int(m["n"])})
    else:
        other.append({"file": name, "kind": "mixed", "localities": 0, "nodes": 0})
out = []
for key, title, note in INFO:
    if key in found:
        ex = sorted(found.pop(key), key=lambda e: (e["localities"], e["kind"] != "flat"))
        out.append({"id": key, "title": title, "note": note, "examples": ex})
for key, ex in sorted(found.items()):
    out.append({"id": key, "title": key, "note": "", "examples": ex})
if other:
    out.append({"id": "other", "title": "Mixed traffic", "note": "Point-to-point traffic without a collective, grouped into bursts.", "examples": other})
with open(os.path.join(EX, "index.json"), "w") as f:
    json.dump({"collectives": out}, f, indent=1)
print("examples/index.json: %d groups, %d files" % (len(out), sum(len(c["examples"]) for c in out)))
