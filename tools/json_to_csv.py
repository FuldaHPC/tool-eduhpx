#!/usr/bin/env python3
"""Converts the merged JSON of the old tool (tools/merge_hpx_run.py, EduMPI GUI) to an EduHPX run file (CSV, format 1).

usage: json_to_csv.py <merged run .json> <run .csv> [--nodes N] [--program NAME]

Times are microseconds since the epoch (clock of the first node), -1 = unknown. See docs/run_file_format.md."""
import argparse
import csv
import json

COLUMNS = ["msg", "src", "dst", "size", "group_kind", "group", "action", "chunk",
           "hpx_create", "mpi_send_start", "mpi_send_end", "mpi_send_done", "mpi_recv_start", "mpi_recv_end",
           "hpx_send_event", "hpx_recv", "hpx_done"]


def us(v):
    """-1 for unknown, else the time with at most three decimals"""
    if v is None:
        return "-1"
    return ("%.3f" % v).rstrip("0").rstrip(".")


def row(m):
    end = m.get("mpi_send_end_us")
    isend = m.get("mpi_isend_us")
    rend = m.get("mpi_recv_end_us")
    irecv = m.get("mpi_irecv_us")
    return [
        m.get("id", ""), m["src"], m["dst"], m["size"], m.get("group_kind", "burst"), m.get("group", 1), m.get("action", ""),
        m.get("mpi_chunk_bytes", 0) or 0,
        us(m.get("hpx_create_us")),
        us(end - isend if end is not None and isend is not None else None),
        us(end),
        us(m.get("mpi_send_done_us")),
        us(rend - irecv if rend is not None and irecv is not None and irecv > 0 else None),
        us(rend),
        us(m.get("tracy_send_us")),
        us(m.get("tracy_recv_us")),
        us(m.get("hpx_done_us")),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("json")
    ap.add_argument("csv")
    ap.add_argument("--nodes", type=int, default=0)
    ap.add_argument("--program", default="")
    a = ap.parse_args()
    d = json.load(open(a.json))
    with open(a.csv, "w", newline="") as f:
        f.write("# eduhpx_run_csv 1\n")
        meta = ["run=%s" % d.get("run_id", ""), "localities=%d" % len(d.get("localities", [])), "grouping=%s" % d.get("grouping", "").replace(" ", "_")]
        if a.nodes:
            meta.append("nodes=%d" % a.nodes)
        if a.program:
            meta.append("program=%s" % a.program)
        f.write("# " + " ".join(meta) + "\n")
        w = csv.writer(f, lineterminator="\n")        # the action names contain commas: minimal quoting
        w.writerow(COLUMNS)
        for m in d["messages"]:
            w.writerow(row(m))
    print("%s: %d messages" % (a.csv, len(d["messages"])))


main()
