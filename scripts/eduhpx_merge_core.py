#!/usr/bin/env python3
"""Core of eduhpx-merge (vendored from the EduHPX prototype, tools/merge_hpx_run.py): parcel log + MPI rows -> JSON.
Used through eduhpx-merge; the Tracy input is kept for old runs.

Merge the Tracy parcel messages and the EduMPI rows of one HPX run into one JSON file.

Inputs (one run directory):
  locNNN.msgs.csv   tracy-csvexport -m output of locality NNN (messages: name,total_ns)
  edumpi_rows.csv   raw EduMPI rows of the run inside the broadcast window (edumpi_rows.sh)

What is joined how:
  * Tracy send <-> Tracy recv of a parcel: exact, the parcel id is the same on both sides.
  * parcel <-> EduMPI MPI_Isend / MPI_Irecv: per (source, destination) in time order, by size.
    The MPI message is the parcel plus a constant number of bytes (--header-bytes, 66 in our runs).
  * Tracy time -> wall clock: every locality emits "SYNC begin wall_us=<epoch us>" once, so
    wall_ns = total_ns + (wall_us * 1000 - total_ns of that message), per locality.

Times in the output are microseconds since the epoch (wall clock), like the EduMPI rows.
"""
import argparse
import collections
import csv
import glob
import json
import re
import statistics
import sys

PAT_SEND = re.compile(r"Parcel Send: id=(\w+:\w+) size=(\d+) to=L#(\w+),(\d+)$")
PAT_RECV = re.compile(r"Parcel Recv: id=(\w+:\w+) from=L#(\w+),(\d+)$")
PAT_SYNC = re.compile(r"SYNC (begin|end) wall_us=(\d+) loc=(\d+),(\d+)$")


def read_tracy(run_dir):
    """Return (sync offsets in ns per locality, window us, sends, recvs)."""
    offset = {}
    window = [None, None]
    sends = {}   # parcel id -> dict
    recvs = {}   # parcel id -> dict
    raw = []
    for path in sorted(glob.glob(run_dir + "/loc*.msgs.csv")):
        loc = int(re.search(r"loc(\d+)\.msgs", path)[1])
        with open(path, errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n")
                m = PAT_SYNC.match(line)
                if m:
                    wall_us, tns = int(m[2]), int(m[4])
                    if m[1] == "begin":
                        offset[loc] = wall_us * 1000 - tns
                        window[0] = wall_us if window[0] is None else min(window[0], wall_us)
                    else:
                        window[1] = wall_us if window[1] is None else max(window[1], wall_us)
                    continue
                m = PAT_SEND.match(line)
                if m:
                    raw.append(("s", loc, m[1], int(m[2]), int(m[3]), int(m[4])))
                    continue
                m = PAT_RECV.match(line)
                if m:
                    raw.append(("r", loc, m[1], 0, 0, int(m[3])))
    for kind, loc, pid, size, to, tns in raw:
        if loc not in offset:
            continue          # no clock bridge for this locality: cannot place it on the wall clock
        wall_us = (tns + offset[loc]) / 1000.0
        if kind == "s":
            sends[pid] = {"id": pid, "src": loc, "dst": to, "size": size, "tracy_send_us": wall_us}
        else:
            recvs[pid] = {"dst": loc, "tracy_recv_us": wall_us}
    return offset, window, sends, recvs


def clock_correction(run_dir):
    """Returns off(rank) in microseconds: what to add to a time stamp of that process to get it on the clock of the
    first node. Needs clock_offsets.csv (written by the run script of a multi-node job, offsets between the nodes
    measured with a ping-pong) and the node name of every rank, which the EduMPI rows contain (processorname)."""
    import os
    path = os.path.join(run_dir, "clock_offsets.csv")
    if not os.path.exists(path):
        return lambda rank: 0.0
    offsets = {}
    for line in open(path):
        f = line.strip().split(",")
        if len(f) == 3 and f[0] != "node":
            offsets[f[0]] = float(f[2])
    node_of = {}
    with open(os.path.join(run_dir, "edumpi_rows.csv")) as fh:
        for row in csv.DictReader(fh):
            if row.get("processorname") and row["processrank"] != "":
                node_of.setdefault(int(row["processrank"]), row["processorname"])
    return lambda rank: offsets.get(node_of.get(rank), 0.0)


def read_parcel_log(run_dir, off=lambda rank: 0.0):
    """Tracy-free input: parcels.loc<rank>.csv written by the patched HPX (HPX_PARCEL_LOG).
    Wall-clock times already, so no clock bridge is needed. Returns (localities, window us, sends, recvs)."""
    sends, recvs, locs = {}, {}, set()
    creates, dones = {}, {}        # C: parcel handed to HPX's send path; D: action of the received parcel has run
    for path in sorted(glob.glob(run_dir + "/parcels.loc*.csv")):
        loc = int(re.search(r"parcels\.loc(\d+)\.csv", path)[1])
        locs.add(loc)
        with open(path) as fh:
            for line in fh:
                f = line.rstrip("\n").split(",")
                if f[0] == "S":
                    sends[f[1]] = {"id": f[1], "src": loc, "dst": int(f[3]), "size": int(f[2]), "tracy_send_us": float(f[4]) + off(loc)}
                elif f[0] == "R":
                    recvs[f[1]] = {"dst": loc, "tracy_recv_us": float(f[3]) + off(loc)}
                elif f[0] == "C" and len(f) >= 5:
                    creates[f[1]] = {"action": f[2], "parent_thread": f[3], "hpx_create_us": float(f[4]) + off(loc)}
                elif f[0] == "D" and len(f) >= 3:
                    dones[f[1]] = float(f[2]) + off(loc)
    times = [p["tracy_send_us"] for p in sends.values()] + [r["tracy_recv_us"] for r in recvs.values()]
    window = [min(times), max(times)] if times else [None, None]
    return sorted(locs), window, sends, recvs, creates, dones


def read_edumpi(path, off=lambda rank: 0.0):
    """(src, dst, size) -> [(end_us, call duration us)] sorted by end. The duration is EduMPI's time_diff:
    the length of the MPI_Isend call. For MPI_Irecv it is 0 (posting is instantaneous, the end time is the arrival)."""
    isend = collections.defaultdict(list)
    irecv = collections.defaultdict(list)
    isend_done = collections.defaultdict(list)   # (src, dst) -> completion of a send request (EDUMPI_SEND_COMPLETION)
    with open(path) as fh:
        for row in csv.DictReader(fh):
            if not row["end_us"]:
                continue
            rank, partner = int(row["processrank"]), int(row["partnerrank"])
            dur = float(row.get("dur_us") or 0.0)
            end_us = int(row["end_us"]) + off(int(row["processrank"]))      # on the clock of the first node
            if row["function"] == "MPI_Isend":
                isend[(rank, partner, int(row["senddatasize"]))].append((end_us, dur))
            elif row["function"] == "MPI_Irecv" and partner >= 0:
                irecv[(partner, rank, int(row["recvdatasize"]))].append((end_us, dur))
            elif row["function"] == "MPI_Isend_done":
                # end = completion of the send request, time_diff = completion - start of the MPI_Isend call
                isend_done[(rank, partner)].append({"end": end_us, "start": end_us - dur, "used": False})
    for d in (isend, irecv):
        for v in d.values():
            v.sort()
    return isend, irecv, isend_done


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dir")
    ap.add_argument("--run-id", type=int, required=True, help="EduMPI run id (= Slurm job id)")
    ap.add_argument("--header-bytes", type=int, default=66, help="MPI message size minus parcel size")
    ap.add_argument("--margin-us", type=int, default=5000, help="keep parcels this close to the SYNC window")
    ap.add_argument("--from-us", type=int, help="only parcels from this wall-clock time on (microseconds since the epoch)")
    ap.add_argument("--to-us", type=int, help="only parcels up to this time (e.g. the region a program reports itself)")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()

    clock_off = clock_correction(args.run_dir)
    if glob.glob(args.run_dir + "/parcels.loc*.csv"):
        logged_locs, window, sends, recvs, creates, dones = read_parcel_log(args.run_dir, clock_off)
        offset = {l: 0 for l in logged_locs}
        source = "HPX parcel log"
    else:
        offset, window, sends, recvs = read_tracy(args.run_dir)
        creates, dones = {}, {}
        source = "Tracy"
    if window[0] is None:
        sys.exit("no parcel events found: need parcels.loc*.csv (HPX_PARCEL_LOG) or Tracy exports with SYNC messages")
    lo, hi = window[0] - args.margin_us, (window[1] or window[0]) + args.margin_us
    isend, irecv, isend_done = read_edumpi(args.run_dir + "/edumpi_rows.csv", clock_off)
    if source == "HPX parcel log":
        # the parcel log covers the whole run (start-up, shutdown), the EduMPI rows only the window of interest:
        # keep the parcels inside the time span of the EduMPI rows, otherwise other parcels of the same size
        # would take the places of the matching in time order
        end_times = [t for d in (isend, irecv) for v in d.values() for (t, _dur) in v]
        if end_times:
            lo, hi = min(end_times) - 2000, max(end_times) + 2000
    if args.from_us is not None:
        lo = args.from_us - args.margin_us
    if args.to_us is not None:
        hi = args.to_us + args.margin_us

    # Matching of parcels and MPI messages. HPX notices a send right after MPI_Isend has finished (a few
    # microseconds) and a receive right after the MPI receive has completed, so a parcel belongs to the unused
    # MPI message of the right size that ended just before the HPX event, and not earlier than the parcel was
    # created / the send ended. A parcel for which no message fits these limits stays without MPI data (no arrow):
    # a wrong match would show impossible times.
    #   size of the MPI message: the parcel plus the parcelport header (header_bytes), or, for parcels with large
    #   arguments (zero-copy chunks: the data goes as an MPI message of its own), a message slightly below the
    #   parcel size.
    def pool(table):
        by_pair = collections.defaultdict(list)
        for (src, dst, size), items in table.items():
            for end, dur in items:
                by_pair[(src, dst)].append({"size": size, "end": end, "dur": dur, "used": False})
        for v in by_pair.values():
            v.sort(key=lambda c: c["end"])
        return by_pair

    send_pool, recv_pool = pool(isend), pool(irecv)
    slack_us = 20.0      # tolerance for clock reads of different layers
    after_us = 5.0       # the HPX event may not be earlier than the MPI end by more than this much

    def take(candidates, size_ok, lower, upper):
        for c in reversed(candidates):          # latest end first
            if c["end"] > upper:
                continue
            if c["end"] < lower:
                break
            if not c["used"] and size_ok(c["size"]):
                c["used"] = True
                return c
        return None

    def take_many(candidates, size, lower, upper):
        """A parcel with several zero-copy chunks (e.g. a vector of vectors) goes out as several MPI messages of the same
        pair: take the latest unused ones in the time window whose sizes add up to the parcel size."""
        chosen, total = [], 0
        for c in reversed(candidates):
            if c["end"] > upper:
                continue
            if c["end"] < lower:
                break
            if c["used"] or c["size"] < 1024 or c["size"] >= size:
                continue
            chosen.append(c)
            total += c["size"]
            if total > size:
                return None
            if total >= size - 1024:
                for x in chosen:
                    x["used"] = True
                return chosen
        return None

    messages = []
    unmatched_mpi = chunked = 0
    for p in sorted((p for p in sends.values() if lo <= p["tracy_send_us"] <= hi), key=lambda p: p["tracy_send_us"]):
        rec = dict(p)
        r = recvs.get(p["id"])
        if r:
            rec["tracy_recv_us"] = r["tracy_recv_us"]
        c = creates.get(p["id"])
        if c:
            rec.update(c)
        if p["id"] in dones:
            rec["hpx_done_us"] = dones[p["id"]]
        pair = (p["src"], p["dst"])
        lower = rec.get("hpx_create_us", p["tracy_send_us"] - 5000) - slack_us
        upper = p["tracy_send_us"] + after_us
        size = p["size"]
        exact = lambda sz, size=size: sz == size + args.header_bytes
        chunk = lambda sz, size=size: size - 1024 <= sz < size
        sc = take(send_pool.get(pair, []), exact, lower, upper)
        is_chunk = False
        if sc is None:
            sc = take(send_pool.get(pair, []), chunk, lower, upper)
            is_chunk = sc is not None
        if sc is None:
            # large parcels go out with a different header size (e.g. 18 bytes instead of 66): a message a little above the parcel size
            sc = take(send_pool.get(pair, []), lambda sz, size=size: size <= sz <= size + 128, lower, upper)
        if sc is None:
            many = take_many(send_pool.get(pair, []), size, lower, upper)
            if many:
                last = max(c["end"] for c in many)
                sc = {"end": last, "dur": last - min(c["end"] - c["dur"] for c in many), "size": sum(c["size"] for c in many), "multi": many}
                is_chunk = True
        if sc is None:
            unmatched_mpi += 1
        else:
            rec["mpi_send_end_us"] = sc["end"]
            rec["mpi_isend_us"] = sc["dur"]
            call_start = sc["end"] - sc["dur"]
            for part in sc.get("multi", [sc]):
                start = part["end"] - part["dur"]
                for d in isend_done.get(pair, []):
                    if not d["used"] and abs(d["start"] - start) <= 3:
                        d["used"] = True
                        rec["mpi_send_done_us"] = max(d["end"], rec.get("mpi_send_done_us", 0))   # the send request completed
                        break
            if is_chunk:
                rec["mpi_chunk_bytes"] = sc["size"]
                chunked += 1
            if is_chunk:
                # zero-copy chunk: HPX already logs "parcel received" when the small header has been decoded, the data
                # arrives later. Take the first unused receive of the same size that ends after the send call started.
                for part in sc.get("multi", [sc]):
                    for rc in recv_pool.get(pair, []):
                        if not rc["used"] and rc["size"] == part["size"] and rc["end"] >= part["end"] - part["dur"] - slack_us:
                            rc["used"] = True
                            if rc["end"] >= rec.get("mpi_recv_end_us", 0):      # the parcel has arrived with its last chunk
                                rec["mpi_recv_end_us"] = rc["end"]
                                rec["mpi_irecv_us"] = rc["dur"]      # post -> arrival, if EduMPI ran with EDUMPI_RECV_DURATION=1
                            break
            elif "tracy_recv_us" in rec:
                # a receive cannot complete before the send call has started
                rc = take(recv_pool.get(pair, []), lambda sz, want=sc["size"]: sz == want,
                          sc["end"] - sc["dur"] - slack_us, rec["tracy_recv_us"] + after_us)
                if rc is not None:
                    rec["mpi_recv_end_us"] = rc["end"]
                    rec["mpi_irecv_us"] = rc["dur"]
        messages.append(rec)

    messages.sort(key=lambda m: m.get("mpi_send_end_us", m["tracy_send_us"]))

    # stage durations (us) where both ends exist
    for m in messages:
        if "mpi_send_end_us" in m and "mpi_recv_end_us" in m:
            m["wire_us"] = m["mpi_recv_end_us"] - m["mpi_send_end_us"]
        if "mpi_recv_end_us" in m and "tracy_recv_us" in m:
            m["recv_handling_us"] = m["tracy_recv_us"] - m["mpi_recv_end_us"]
        if "mpi_send_end_us" in m:
            m["send_completion_us"] = m["tracy_send_us"] - m["mpi_send_end_us"]
        if "hpx_create_us" in m and "mpi_send_end_us" in m:
            m["hpx_pre_send_us"] = m["mpi_send_end_us"] - m["hpx_create_us"]
        if "hpx_done_us" in m and "tracy_recv_us" in m:
            m["action_us"] = m["hpx_done_us"] - m["tracy_recv_us"]

    # Grouping, so that a run can be looked at piece by piece.
    # 1) Collectives. The action name of a request of an HPX collective contains the operation
    #    (hpx::traits::communication::<op>_tag). Instance k of an operation = the k-th request of every
    #    locality for that operation. The reply is created while the action of the request runs, on the
    #    locality that received the request and addressed to the sender, so it is found by time.
    # 2) Everything else: bursts. A new burst starts when no parcel has been in flight for a while.
    def start_of(x):
        return x.get("hpx_create_us", x.get("mpi_send_end_us", x["tracy_send_us"]))

    def end_of(x):
        return x.get("hpx_done_us", x.get("tracy_recv_us", x.get("mpi_recv_end_us", x["tracy_send_us"])))

    def collective_op(name):
        found = re.search(r"communication::(\w+?)_tag", name or "")
        return found.group(1) if found else None

    requests = [m for m in messages if collective_op(m.get("action"))]
    seen = collections.Counter()
    for m in sorted(requests, key=start_of):
        op = collective_op(m["action"])
        seen[(op, m["src"])] += 1
        m["group_kind"], m["group"] = op, seen[(op, m["src"])]
    replies = collections.defaultdict(list)          # (sender, receiver) -> parcels that could be replies
    for m in messages:
        if "group_kind" not in m and "hpx_create_us" in m:
            replies[(m["src"], m["dst"])].append(m)
    reply_slack_us = 100.0
    for m in sorted(requests, key=start_of):
        if "tracy_recv_us" not in m or "hpx_done_us" not in m:
            continue
        for r in replies.get((m["dst"], m["src"]), []):
            if "group_kind" not in r and m["tracy_recv_us"] - reply_slack_us <= r["hpx_create_us"] <= m["hpx_done_us"] + reply_slack_us:
                r["group_kind"], r["group"] = m["group_kind"], m["group"]
                break
    rest = sorted((m for m in messages if "group_kind" not in m), key=start_of)
    lives = sorted(end_of(m) - start_of(m) for m in rest)
    gap_us = max(100.0, 3 * lives[len(lives) // 2]) if lives else 100.0
    g, group_end = 0, None
    for m in rest:
        if group_end is None or start_of(m) - group_end > gap_us:
            g += 1
            group_end = end_of(m)
        group_end = max(group_end, end_of(m))
        m["group_kind"], m["group"] = "burst", g
    grouping = "collectives and bursts"

    out = {
        "run_id": args.run_id,
        "window_us": [lo, hi],
        "localities": sorted(set(offset) | {m["src"] for m in messages} | {m["dst"] for m in messages}),
        "header_bytes": args.header_bytes,
        "messages": messages,
        "source": source,
        "grouping": grouping,
        "group_gap_us": gap_us,
        "notes": [
            "tracy_send_us is taken when the parcel send has completed (write handler), not when it started.",
            "mpi_*_end_us are the end times of MPI_Isend / MPI_Irecv in EduMPI.",
            "wire_us = mpi_recv_end - mpi_send_end, only meaningful if the nodes' clocks are in sync.",
        ],
    }
    with open(args.output, "w") as fh:
        json.dump(out, fh)

    # short report
    n = len(messages)
    both = sum(1 for m in messages if "mpi_send_end_us" in m and "mpi_recv_end_us" in m)
    with_recv = sum(1 for m in messages if "tracy_recv_us" in m)
    kinds = collections.Counter()
    for kind in {m["group_kind"] for m in messages}:
        kinds[kind] = len({m["group"] for m in messages if m["group_kind"] == kind})
    print("groups: " + ", ".join(f"{k} x{v}" for k, v in sorted(kinds.items())) +
          f";  {n} parcels in the window; matched to an EduMPI send: {n - unmatched_mpi} "
          f"(of them {chunked} as zero-copy chunks); to send+recv: {both}; with an HPX recv: {with_recv}")
    for field, label in (("hpx_pre_send_us", "HPX parcel created -> MPI send end"),
                         ("wire_us", "MPI send end -> MPI recv end"),
                         ("recv_handling_us", "MPI recv end -> HPX parcel recv"),
                         ("action_us", "HPX parcel received -> action done"),
                         ("send_completion_us", "MPI send end -> HPX parcel send event")):
        vals = sorted(m[field] for m in messages if field in m)
        if vals:
            print(f"  {label:42s} median {statistics.median(vals):8.0f} us  "
                  f"p90 {vals[int(len(vals) * 0.9)]:8.0f}  min {vals[0]:8.0f}  max {vals[-1]:8.0f}  (n={len(vals)})")


if __name__ == "__main__":
    main()
