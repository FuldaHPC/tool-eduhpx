import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Dialogs

// EduHPX: one HPX run (parcel events of HPX + MPI messages, a run file made by eduhpx-merge), shown group by
// group (one broadcast, one barrier, one burst of other traffic, ...) in three views.
//   By locality: one lane per locality. In its lane a locality shows what it does:
//       orange       HPX prepares the send     (parcel created -> start of the MPI_Isend call)
//       blue         MPI send                  (the MPI_Isend call; light blue: HPX sees the send request still open)
//       blue         MPI receive               (until the receive is complete)
//       light orange HPX picks it up           (MPI has the message, HPX has not yet)
//       yellow       the action runs
//     A blue arrow connects the MPI send of the sender with the MPI receive on the receiver.
//   By message: one row per message with the same colours.
// The strip on top has one bar per group (height ~ sqrt(duration)); click a bar or use the arrows.
ApplicationWindow {
    id: hpxWindow
    visible: true
    width: 1280
    height: 860
    title: run.loaded ? "EduHPX - " + run.name : "EduHPX"
    color: "#4d4d4d"
    minimumWidth: 900
    minimumHeight: 660

    // File menu: open a run file, the examples that are built into the program
    menuBar: MenuBar {
        Menu {
            title: "File"
            MenuItem { text: "Open run file..."; onTriggered: fileDialog.open() }
            MenuItem { text: "Start page"; enabled: run.loaded; onTriggered: run.unload() }
            MenuItem { text: "Examples..."; onTriggered: examplesDialog.open() }
            MenuSeparator { }
            MenuItem { text: "Quit"; onTriggered: Qt.quit() }
        }
        Menu {
            title: "Help"
            MenuItem { text: "About EduHPX"; onTriggered: aboutDialog.open() }
        }
    }

    readonly property color preColor: "#fb8c00"          // HPX prepares: orange
    readonly property color waitColor: "#8d8d8d"           // waiting for the data of the parent (a dependency, not work)
    readonly property color mpiColor: "#4fc3f7"
    readonly property color mpiSendColor: "#00ff00"        // MPI send: the green of the 3D view for 100 % sending, RGB(0, 255, 0)
    readonly property color mpiRecvColor: "#ff0000"        // MPI receive: the red of the 3D view for 100 % receiving, RGB(255, 0, 0)
    readonly property color recvColor: "#ffb74d"         // HPX picks up: light orange
    readonly property color actionColor: "#ffe082"

    property var groups: []         // { kind, k, total, rows, start, end }
    property int current: 0
    property var rows: []           // rows of the current group
    property double viewStart: 0
    property double viewEnd: 1
    property real sumWait: 0        // waiting for the data of the parent (tree broadcast)
    property real sumPre: 0         // HPX prepares the send
    property real sumMpi: 0         // MPI send / receive
    property real sumPick: 0        // HPX picks the message up
    property real sumAction: 0      // the action runs
    property real sumParent: 0      // broadcast: the requests wait at the parent until the reply is created
    property real sumHpx: 0
    property real sumBytes: 0
    property real runBytes: 0
    property int senders: 0         // localities that send at least one message in this group
    property int localitiesInGroup: 0
    property int maxFanOut: 0       // largest number of different receivers of one sender
    property int fanOutLoc: -1
    property int runParcels: 0
    property int skipped: 0         // parcels without MPI data (not shown)
    property int hoverIndex: -1
    property string viewMode: "locality"   // locality | message
    property var laneInfo: []
    property var laneMsgs: []
    property int laneHover: -1
    property real emptyCall: 244         // size of a call without a value (the smallest call of the run)
    property real emptyAnswer: 154       // size of an answer without a value (the smallest answer of the run)
    property real scrollY: 0            // vertical scrolling of the locality and message views
    property real contentH: 0           // height the current view would need
    function scrollBy(dy, viewH) {
        scrollY = Math.max(0, Math.min(scrollY + dy, Math.max(contentH - viewH, 0)));
    }
    property string arrowFilter: "all"   // all | data | requests: which arrows the lane view draws
    property bool ackOnly: false         // the small messages are answers that follow the data (a set), not requests that precede it
    property bool hasDataClass: false    // the group has large (data) and small (request) messages
    // broadcast model: who asked whom (tree) and the critical path
    property bool hasTree: false
    property bool treeUp: false          // the data of the tree moves up (reduce, gather) instead of down
    readonly property bool pathOn: hasTree && pathLength > 0
    readonly property bool showPath: pathOn && criticalOn      // summary: the critical path (real time), else all messages added up
    property int pathHops: 0
    property real sumWire: 0        // MPI transfer only: from the end of the send call to the end of the receive
    // the group that is shown; null while the list of groups and the index are out of step (a new file, the start page)
    readonly property var currentGroup: current >= 0 && current < groups.length ? groups[current] : null
    readonly property real groupSpan: currentGroup ? currentGroup.end - currentGroup.start : 0
    property var treeNodes: []           // { loc, depth, x }
    property var treeNodeMap: ({})
    property var treeEdges: []           // { p, c, data, req } parent p answers the request of child c with the data
    property int treeLeaves: 1
    property int treeDepth: 0
    property double treeStart: 0
    property int treeHover: -1
    property bool criticalOn: false      // highlight the critical path in all views and show it in the summary (button)
    property var pathSegs: []            // { kind: prepare | mpi | pick | action, a, b }
    property real pathLength: 0
    property real pathStart: 0           // start and end of the path, after the first event of the group
    property real pathEnd: 0
    property real pathPrepare: 0
    property real pathMpi: 0
    property real pathPick: 0
    property real pathAction: 0
    property real pathParent: 0          // the request waits at the parent until the reply is created
    readonly property color parentColor: "#c98a5e"       // a request waits at its parent: warm brown
    property string pathChain: ""

    // "the send request is still open": dark green with diagonal stripes in the green of the send, so that it cannot be
    // mistaken for a finished send
    function openRequest(ctx, x, y, w, h) {
        ctx.save();
        ctx.beginPath();
        ctx.rect(x, y, w, h);
        ctx.clip();
        ctx.fillStyle = "#0b3a0b";
        ctx.fillRect(x, y, w, h);
        ctx.strokeStyle = mpiSendColor;
        ctx.lineWidth = 1.4;
        for (let k = -h; k < w; k += 5) {
            ctx.beginPath();
            ctx.moveTo(x + k, y + h);
            ctx.lineTo(x + k + h, y);
            ctx.stroke();
        }
        ctx.restore();
    }

    // blue frame around an MPI bar (send and receive together are MPI)
    function mpiFrame(ctx, x, y, w, h) {
        ctx.strokeStyle = mpiColor;
        ctx.lineWidth = 1.6;
        ctx.strokeRect(x + 0.8, y + 0.8, Math.max(w - 1.6, 0.5), Math.max(h - 1.6, 0.5));
    }

    // end of the waiting for the data of the parent (= start of the real preparation of the send)
    function waitEnd(r) {
        if (r.tc < 0)
            return r.t0s;
        return r.tw > r.tc ? Math.min(r.tw, r.t0s) : r.tc;
    }

    // should the arrow of this message be drawn? "data" = the large messages, "requests" = the small ones
    function arrowShown(r) {
        if (arrowFilter === "all" || !hasDataClass)
            return true;
        return arrowFilter === "data" ? r.big : !r.big;
    }

    function fmtUs(v) {
        if (v === undefined || v === null)
            return "-";
        return v >= 1000 ? (v / 1000).toFixed(2) + " ms" : v.toFixed(0) + " us";
    }
    function fmtSize(b) {
        return b >= 1048576 ? (b / 1048576).toFixed(1) + " MiB" : b >= 1024 ? (b / 1024).toFixed(b >= 10240 ? 0 : 1) + " KiB" : b + " B";
    }
    function actionTag(name) {
        if (!name)
            return "";
        const base = name.split("<")[0].split("::").pop();
        if (base.indexOf("base_lco_with_value") === 0 || base.indexOf("set_value") === 0)
            return "reply";
        const m = base.match(/communication_(\w+?)_(direct_)?action/);
        return m ? m[1] : base.slice(0, 16);
    }
    function kindLabel(kind) {
        const t = String(kind).replace(/_/g, "-");
        return t.charAt(0).toUpperCase() + t.slice(1);
    }
    // share of the time of all messages of this group, as text
    function pct(v) {
        const total = sumWait + sumPre + sumMpi + sumPick + sumParent + sumAction;
        return total > 0 ? (100 * v / total).toFixed(0) + " %" : "-";
    }
    function groupLabel(g) {
        return g ? kindLabel(g.kind) + " " + g.k + " of " + g.total : "";
    }

    // open a run file (a URL; also called from the command line and by drag and drop)
    function openFile(url) {
        run.load(url);
    }
    // for the tests: the critical path of every group as JSON (eduhpx with EDUHPX_PATH_REPORT=1 prints it)
    function pathReport() {
        const out = [];
        for (let i = 0; i < groups.length; ++i) {
            select(i);
            const base = {kind: groups[i].kind, k: groups[i].k, messages: rows.length};
            if (!hasTree) {
                out.push(Object.assign(base, {tree: false}));
                continue;
            }
            let covered = 0;
            for (const sg of pathSegs)
                covered += sg.b - sg.a;
            const edgeList = treeEdges.map(e => [e.p, e.c, e.data.src, e.data.dst]);
            out.push(Object.assign(base, {tree: true, up: treeUp, chain: pathChain, hops: pathHops, depth: treeDepth, nodes: treeNodes.length,
                                          length: pathLength, span: groupSpan, covered: covered, start: pathStart, end: pathEnd,
                                          parts: {prepare: pathPrepare, mpi: pathMpi, pick: pathPick, parent: pathParent, action: pathAction},
                                          edges: edgeList, segs: pathSegs.map(x => [x.kind, Math.round(x.a - groups[i].start), Math.round(x.b - groups[i].start)])}));
        }
        select(0);
        return JSON.stringify(out);
    }
    function showStartPage() {          // also used by the headless preview
        run.unload();
    }
    // for the headless preview (eduhpx --render): show a group / a view
    function showGroup(kind, k) {
        for (let i = 0; i < groups.length; ++i)
            if (groups[i].kind === kind && groups[i].k === k) {
                select(i);
                return;
            }
        select(0);
    }
    function showView(mode) {
        viewMode = mode;
        lanes.requestPaint();
        waterfall.requestPaint();
        tree.requestPaint();
    }

    function build() {
        const byKey = {};
        const lostByKey = {};
        let skippedCount = 0;
        for (let i = 0; i < run.messages.length; ++i) {
            const m = run.messages[i];
            if (m.mpi_send_end_us === undefined || m.mpi_recv_end_us === undefined) {
                ++skippedCount;
                if (m.group_kind !== undefined && m.group !== undefined)       // kept for the tree: its parcel is known, only the MPI message is not
                    (lostByKey[m.group_kind + "#" + m.group] = lostByKey[m.group_kind + "#" + m.group] || []).push(
                        {src: m.src, dst: m.dst, size: m.size, action: m.action || "", tc: m.hpx_create_us !== undefined ? m.hpx_create_us : -1,
                         t0: m.mpi_send_end_us !== undefined ? m.mpi_send_end_us : -1,
                         tr: m.tracy_recv_us !== undefined ? m.tracy_recv_us : -1, td: m.hpx_done_us !== undefined ? m.hpx_done_us : -1});
                continue;
            }
            const t0 = m.mpi_send_end_us, t1 = m.mpi_recv_end_us;
            const ds = m.mpi_isend_us !== undefined ? Math.max(m.mpi_isend_us, 0) : 0;
            const t0s = t0 - ds;
            const chunk = m.mpi_chunk_bytes !== undefined;
            // HPX receive event: normally after the MPI receive; for zero-copy parcels HPX logs it when the small
            // header is decoded, the data (the MPI message) arrives later
            const trRaw = m.tracy_recv_us !== undefined ? m.tracy_recv_us : t1;
            const tr = chunk ? trRaw : Math.max(trRaw, t1);
            const tc = m.hpx_create_us !== undefined ? Math.min(m.hpx_create_us, t0s) : -1;
            const td = m.hpx_done_us !== undefined && !chunk ? Math.max(m.hpx_done_us, tr) : -1;
            const ts = m.tracy_send_us !== undefined ? m.tracy_send_us : -1;
            // when the send request completed: EduMPI (EDUMPI_SEND_COMPLETION), otherwise the moment HPX noticed it
            const tdone = m.mpi_send_done_us !== undefined ? m.mpi_send_done_us : -1;
            const rq = tdone >= 0 ? tdone : (ts > t0 ? ts : -1);
            // start of the MPI receive bar: when EduMPI knows the post time of the receive (time_diff of MPI_Irecv),
            // otherwise the start of the send call (the receive cannot complete earlier)
            const rd = m.mpi_irecv_us !== undefined ? m.mpi_irecv_us : 0;
            const rs = Math.min(rd > 0 ? Math.max(t1 - rd, t0s) : t0s, t1);
            const row = {src: m.src, dst: m.dst, size: m.size, tc: tc, t0s: t0s, t0: t0, t1: t1, tr: tr, td: td, ts: ts, rq: rq, rs: rs,
                         action: m.action || "", chunk: chunk, exact: tdone >= 0, tw: -1};
            const kind = m.group_kind !== undefined ? m.group_kind : "burst";
            const idx = m.group !== undefined ? m.group : 1;
            row.kind = kind;
            row.idx = idx;
            const key = kind + "#" + idx;
            (byKey[key] = byKey[key] || []).push(row);
        }
        const list = [];
        const total = {};
        for (const key of Object.keys(byKey)) {
            const rws = byKey[key];
            let start = Infinity, end = 0;
            for (const r of rws) {
                start = Math.min(start, r.tc >= 0 ? r.tc : r.t0s, r.rs);
                end = Math.max(end, r.t0, r.t1, r.tr, r.td, r.ts, r.rq);
            }
            // Tree broadcast: a locality that forwards the data to its children hands HPX the parcel early (with a future
            // for data that has not arrived yet). Until its own data has arrived it is waiting, not preparing.
            if (rws[0].kind === "broadcast") {
                let maxS = 0, minS = Infinity;
                for (const r of rws) {
                    maxS = Math.max(maxS, r.size);
                    minS = Math.min(minS, r.size);
                }
                if (maxS > 2 * minS) {
                    const into = {};                                   // the data message every locality receives
                    for (const r of rws)
                        if (r.size >= maxS / 2)
                            into[r.dst] = r;
                    for (const r of rws) {
                        const up = r.size >= maxS / 2 ? into[r.src] : undefined;
                        if (up && r.tc >= 0 && up.t1 > r.tc)
                            r.tw = up.t1;
                    }
                }
            }
            rws.sort((a, b) => (a.tc >= 0 ? a.tc : a.t0s) - (b.tc >= 0 ? b.tc : b.t0s));
            list.push({kind: rws[0].kind, k: rws[0].idx, rows: rws, start: start, end: end, lost: lostByKey[key] || []});
            total[rws[0].kind] = (total[rws[0].kind] || 0) + 1;
        }
        list.sort((a, b) => a.start - b.start);
        for (const g of list)
            g.total = total[g.kind];
        let bytes = 0, parcels = 0;
        for (const g of list)
            for (const r of g.rows) {
                bytes += r.size;
                ++parcels;
            }
        let ea = Infinity, ec = Infinity;
        for (const g of list)
            for (const r of g.rows) {
                if (/set_value_action/.test(r.action))
                    ea = Math.min(ea, r.size);
                else if (/communication_(get|set)_direct_action/.test(r.action))
                    ec = Math.min(ec, r.size);
            }
        hpxWindow.emptyCall = ec < Infinity ? ec : 244;
        hpxWindow.emptyAnswer = ea < Infinity ? ea : 154;
        hpxWindow.runBytes = bytes;
        hpxWindow.runParcels = parcels;
        hpxWindow.skipped = skippedCount;
        hpxWindow.groups = list;
        select(0);
    }

    // broadcast: the action of a small request is the time it waits at the parent until the reply is created
    function isRequestWait(r) {
        return currentGroup !== null && currentGroup.kind === "broadcast" && !r.big;
    }

    function select(i) {
        if (groups.length === 0) {
            rows = [];
            laneInfo = [];
            laneMsgs = [];
            strip.requestPaint();
            waterfall.requestPaint();
            lanes.requestPaint();
            return;
        }
        current = Math.max(0, Math.min(i, groups.length - 1));
        const g = groups[current];
        laneHover = -1;
        hoverIndex = -1;
        scrollY = 0;
        rows = g.rows;
        const dur = Math.max(g.end - g.start, 1);
        viewStart = g.start - dur * 0.03;
        viewEnd = g.end + dur * 0.03;
        let wait = 0, pre = 0, mpi = 0, pick = 0, act = 0, par = 0, wire = 0, bytes = 0;
        for (const r of rows) {
            wait += r.tc >= 0 ? waitEnd(r) - r.tc : 0;
            pre += r.tc >= 0 ? r.t0s - waitEnd(r) : 0;
            mpi += Math.max(r.t0, r.t1, r.rq) - r.t0s;
            wire += Math.max(r.t1 - r.t0, 0);
            pick += Math.max(r.tr - r.t1, 0);
            if (g.kind === "broadcast" && !r.big)
                par += r.td >= 0 ? r.td - r.tr : 0;
            else
                act += r.td >= 0 ? r.td - r.tr : 0;
            bytes += r.size;
        }
        sumWait = wait;
        sumPre = pre;
        sumMpi = mpi;
        sumPick = pick;
        sumAction = act;
        sumParent = par;
        sumWire = wire;
        sumHpx = pre + pick + act;
        sumBytes = bytes;
        // fan-out: to how many different localities does a sender send? Only the data direction counts (the large
        // messages), not the small requests that every locality sends. Flat broadcast: one sender, all others receive.
        let maxSize = 0, minSize = Infinity;
        for (const r of rows) {
            maxSize = Math.max(maxSize, r.size);
            minSize = Math.min(minSize, r.size);
        }
        let dataOnly = maxSize > 2 * minSize;
        // A collective is calls (the actions get_direct / set_direct of a locality to its parent) and answers. That tells
        // the requests from the data whatever the sizes are: for a get the data is in the answer, for a set in the call.
        const callRe = /communication_(get|set)_direct_action/;
        let nCalls = 0, nSets = 0;
        for (const r of rows) {
            r.isCall = callRe.test(r.action);
            if (r.isCall) {
                ++nCalls;
                if (/communication_set_direct_action/.test(r.action))
                    ++nSets;
            }
        }
        if (nCalls > 0 && nCalls < rows.length) {
            // Data is what carries a payload: the call of a set, the answer of a get, and the answer of a set that is
            // more than the empty answer (all-gather sends the gathered result back that way). The rest are requests.
            const callType = {};
            for (const r of rows)
                if (r.isCall)
                    callType[r.src + ">" + r.dst] = /communication_set_direct_action/.test(r.action) ? "set" : "get";
            const setMajority = nSets * 2 > nCalls;
            dataOnly = true;
            hasDataClass = true;
            for (const r of rows) {
                if (r.isCall) {
                    r.big = callType[r.src + ">" + r.dst] === "set" || r.size > emptyCall + 100;   // a get that carries data (all-gather)
                } else {
                    const ct = callType[r.dst + ">" + r.src] || (setMajority ? "set" : "get");
                    r.big = ct === "get" || r.size > emptyAnswer + 32;
                }
            }
        } else {
            hasDataClass = dataOnly;
            for (const r of rows)
                r.big = !dataOnly || r.size >= maxSize / 2;
        }
        ackOnly = hasDataClass && !rows.some(r => !r.big && r.isCall);
        const to = {};
        const all = {};
        for (const r of rows) {
            all[r.src] = true;
            all[r.dst] = true;
            if (dataOnly && !r.big)
                continue;
            (to[r.src] = to[r.src] || {})[r.dst] = true;
        }
        let best = 0, bestLoc = -1, count = 0;
        for (const src of Object.keys(to)) {
            ++count;
            const n = Object.keys(to[src]).length;
            if (n > best) { best = n; bestLoc = parseInt(src); }
        }
        senders = count;
        localitiesInGroup = Object.keys(all).length;
        maxFanOut = best;
        fanOutLoc = bestLoc;
        hoverIndex = -1;
        buildLanes();
        buildBroadcastModel();
        if (viewMode === "tree" && !hasTree)
            viewMode = "locality";
        strip.requestPaint();
        waterfall.requestPaint();
        lanes.requestPaint();
        tree.requestPaint();
    }

    // zoom / move the time axis (inside the limits: at least 10 us, at most a few times the group)
    function setView(start, end) {
        if (groups.length === 0)
            return;
        const g = groups[current];
        const width = Math.max(10, Math.min(end - start, Math.max(g.end - g.start, 1) * 6));
        viewStart = start;
        viewEnd = start + width;
        lanes.requestPaint();
        waterfall.requestPaint();
    }

    // One lane per locality. Per message two pieces of work are placed: on the sender from the creation of the
    // parcel until the end of the MPI send, on the receiver from the start of the MPI receive until the action is
    // done. Pieces that overlap in time go on different tracks of the same lane.
    function buildLanes() {
        const byLoc = {};
        const msgs = [];
        for (let i = 0; i < rows.length; ++i) {
            const r = rows[i];
            const pre = {msg: i, loc: r.src, a: r.tc >= 0 ? r.tc : r.t0s, b: Math.max(r.t0, r.rq), track: 0};
            const rcv = {msg: i, loc: r.dst, a: Math.min(r.rs, r.tr), b: Math.max(r.t1 + 1, r.td >= 0 ? r.td : r.tr), track: 0};
            (byLoc[r.src] = byLoc[r.src] || []).push(pre);
            (byLoc[r.dst] = byLoc[r.dst] || []).push(rcv);
            msgs.push({row: r, pre: pre, rcv: rcv});
        }
        const lanesList = [];
        for (const loc of Object.keys(byLoc).map(x => parseInt(x)).sort((a, b) => a - b)) {
            const pieces = byLoc[loc].sort((a, b) => a.a - b.a);
            const ends = [];
            for (const piece of pieces) {
                let t = 0;
                while (t < ends.length && ends[t] > piece.a)
                    ++t;
                ends[t] = piece.b;
                piece.track = t;
            }
            lanesList.push({loc: loc, tracks: Math.max(ends.length, 1), y0: 0, h: 0});
        }
        laneHover = -1;
        hoverIndex = -1;
        laneInfo = lanesList;
        laneMsgs = msgs;
    }

    // Tree of a broadcast and its critical path. Needs a group with large (data) and small (request) messages:
    // every locality sends one request to its parent and gets the data back from it.
    function buildBroadcastModel() {
        for (const r of rows)
            r.crit = false;
        hasTree = false;
        treeUp = false;
        treeEdges = [];
        treeNodes = [];
        treeNodeMap = ({});
        pathSegs = [];
        pathLength = pathPrepare = pathMpi = pathPick = pathAction = pathParent = 0;
        pathHops = 0;
        pathChain = "";
        treeHover = -1;
        const g = groups[current];
        if (g && g.kind !== "broadcast" && g.kind !== "burst" && g.kind !== "barrier") {
            buildGenericTree(g);
            return;
        }
        if (!g || g.kind !== "broadcast")
            return;                                          // burst, barrier: no tree
        // A broadcast with large data messages has its own model (it knows the wait for the data of the parent). The
        // broadcast inside an all-reduce carries small values only: it is built like the other collectives.
        let maxSz = 0, minSz = Infinity;
        for (const r of rows) {
            maxSz = Math.max(maxSz, r.size);
            minSz = Math.min(minSz, r.size);
        }
        if (!hasDataClass || maxSz <= 2 * minSz) {
            buildGenericTree(g);
            return;
        }
        const into = {};
        const asks = {};
        const children = {};
        const isReceiver = {};
        for (const r of rows) {
            if (r.big) {
                into[r.dst] = r;
                isReceiver[r.dst] = true;
                (children[r.src] = children[r.src] || []).push(r.dst);
            } else {
                asks[r.src] = r;
            }
        }
        let root = -1;
        for (const r of rows)
            if (r.big && !isReceiver[r.src]) {
                root = r.src;
                break;
            }
        if (root < 0)
            return;

        // layout of the tree: depth = level, x = position among the leaves
        const map = {};
        let leaf = 0, maxDepth = 0;
        const place = (loc, depth) => {
            maxDepth = Math.max(maxDepth, depth);
            const kids = (children[loc] || []).slice().sort((a, b) => a - b);
            let x;
            if (kids.length === 0) {
                x = leaf++;
            } else {
                let sum = 0;
                for (const k of kids)
                    sum += place(k, depth + 1);
                x = sum / kids.length;
            }
            map[loc] = {loc: loc, depth: depth, x: x, leaf: kids.length === 0};
            return x;
        };
        place(root, 0);
        const edges = [];
        for (const loc of Object.keys(map).map(x => parseInt(x)).sort((a, b) => a - b))
            if (loc !== root && into[loc])
                edges.push({p: into[loc].src, c: loc, data: into[loc], req: asks[loc]});
        treeNodeMap = map;
        treeNodes = Object.keys(map).map(k => map[k]);
        treeEdges = edges;
        treeLeaves = Math.max(leaf, 1);
        treeDepth = maxDepth;
        treeStart = g.start;
        hasTree = true;

        // critical path: from the data message that is finished last, backwards. A locality that waited for the data of
        // its parent continues at the hop of the parent; a child of the root continues in its own request and the
        // handling of it at the root.
        let last = null, lastEnd = -Infinity;
        for (const r of rows)
            if (r.big) {
                const e = Math.max(r.t1, r.tr, r.td);
                if (e > lastEnd) {
                    lastEnd = e;
                    last = r;
                }
            }
        const segs = [];
        const hops = [];
        const add = (kind, a, b, row) => {
            row.crit = true;
            if (b > a)
                segs.push({kind: kind, a: a, b: b});
        };
        let cur = last, isFinal = true;
        while (cur) {
            hops.push(cur);
            if (isFinal) {
                add("action", cur.tr, cur.td, cur);
                add("pick", cur.t1, cur.tr, cur);
                isFinal = false;
            }
            add("mpi", cur.t0s, Math.max(cur.t0, cur.t1, cur.rq), cur);
            const we = waitEnd(cur);
            add("prepare", we, cur.t0s, cur);
            const up = into[cur.src];
            if (up) {                                         // a forwarding locality sends on what it received, whenever HPX created the parcel
                cur = up;
                continue;
            }
            const rq = asks[cur.dst];
            if (rq) {
                add("parent", rq.tr, Math.max(cur.tc, rq.tr), rq);
                add("pick", rq.t1, rq.tr, rq);
                add("mpi", rq.t0s, Math.max(rq.t0, rq.t1, rq.rq), rq);
                add("prepare", waitEnd(rq), rq.t0s, rq);
            }
            break;
        }
        let a0 = Infinity, prep = 0, mpi = 0, pick = 0, act = 0, par = 0;
        for (const sg of segs) {
            a0 = Math.min(a0, sg.a);
            if (sg.kind === "prepare") prep += sg.b - sg.a;
            else if (sg.kind === "mpi") mpi += sg.b - sg.a;
            else if (sg.kind === "pick") pick += sg.b - sg.a;
            else if (sg.kind === "parent") par += sg.b - sg.a;
            else act += sg.b - sg.a;
        }
        pathSegs = segs;
        pathLength = lastEnd - a0;
        pathStart = a0 - g.start;
        pathEnd = lastEnd - g.start;
        pathPrepare = prep;
        pathMpi = mpi;
        pathPick = pick;
        pathAction = act;
        pathParent = par;
        pathHops = hops.length;
        const names = hops.length > 0 ? [hops[hops.length - 1].src] : [];
        for (let i = hops.length - 1; i >= 0; --i)
            names.push(hops[i].dst);
        pathChain = names.map(l => "L#" + l).join(" → ");
    }

    // Tree of any other collective (reduce, gather, scatter, ...; also the star of a flat one). Every edge of the tree
    // carries two messages, one each way; the larger one is the data and its direction says whether the data moves up
    // (reduce, gather) or down (scatter ...) the tree. The critical path is the chain that finishes the group.
    function buildGenericTree(g) {
        // Every edge of the tree has a call of the child to its parent (the action get_direct or set_direct) and the
        // answer of the parent. For a get the data comes back in the answer (down the tree); a set carries the data in
        // the call (up the tree). Without such an action the larger message of the pair is taken as the data.
        const callRe = /communication_(get|set)_direct_action/;
        const pairs = {};
        for (const r of rows) {
            const key = Math.min(r.src, r.dst) + "-" + Math.max(r.src, r.dst);
            (pairs[key] = pairs[key] || []).push(r);
        }
        // parcels without an MPI message are known from the parcel log; they take part in the tree where no row exists
        // for their direction (their times: end of the send call, HPX receive)
        for (const lp of (g.lost || [])) {
            const key = Math.min(lp.src, lp.dst) + "-" + Math.max(lp.src, lp.dst);
            const list = pairs[key] = pairs[key] || [];
            if (list.some(m => m.src === lp.src && m.dst === lp.dst))
                continue;
            const t0 = lp.t0 >= 0 ? lp.t0 : (lp.tc >= 0 ? lp.tc : lp.tr);
            const t1 = Math.max(t0, lp.tr);
            if (t0 < 0)
                continue;
            list.push({src: lp.src, dst: lp.dst, size: lp.size, tc: lp.tc >= 0 ? Math.min(lp.tc, t0) : t0, t0s: t0, t0: t0, t1: t1,
                       tr: t1, td: lp.td >= 0 ? Math.max(lp.td, t1) : -1, ts: -1, rq: t1, rs: t1, action: lp.action, chunk: false,
                       exact: false, tw: -1, kind: g.kind, idx: g.k, missing: true});
        }
        const found = [];                                    // {call, answer, set}
        const nodes = {};
        let calls = 0, sets = 0;
        for (const key of Object.keys(pairs)) {
            const ms = pairs[key].slice().sort((a, b) => b.size - a.size);
            let call = ms.find(m => callRe.test(m.action));
            let isSet, lostCall = false;
            if (call) {
                isSet = /communication_set_direct_action/.test(call.action);
                ++calls;
            } else {
                call = ms[ms.length - 1];                    // no action name: the smaller message is the call
                isSet = false;
                lostCall = ms.length === 1;                  // only one message is known: may be an answer whose call is missing
            }
            const answer = ms.find(m => m !== call && m.src === call.dst && m.dst === call.src);
            nodes[call.src] = nodes[call.dst] = true;
            if (isSet)
                ++sets;
            found.push({call: call, answer: answer, set: isSet, lost: lostCall});
        }
        const nodeCount = Object.keys(nodes).length;
        if (nodeCount < 3 || found.length >= nodeCount || nodeCount - found.length > 4)
            return;                                          // not a tree (or a few of them: the halves of a hierarchical all-to-all)
        const up = sets * 2 > found.length;                  // the data moves towards the root
        for (const f of found) {
            f.p = f.call.dst; f.c = f.call.src;
            if (calls > 0 && f.lost && !callRe.test(f.call.action)) {
                f.p = f.call.src; f.c = f.call.dst;          // the lone message is an answer: its call was lost, turn the direction
                f.answer = f.call;
                f.call = null;
            }
        }
        const edges = [], children = {}, parentRow = {}, hasParent = {};
        for (const f of found) {
            const p = f.p, c = f.c;
            if (hasParent[c])
                return;                                      // a node with two parents: not a tree
            hasParent[c] = true;
            let data = up ? (f.call || f.answer) : (f.answer || f.call);
            if (up && !f.call && f.answer) {
                // the data parcel has no MPI message: it is known from the parcel log, its arrival is the later of the
                // end of the send call and the HPX receive; without it the answer of the parent stands in
                const a = f.answer;
                const lp = (g.lost || []).find(x => x.src === c && x.dst === p && callRe.test(x.action));
                let t1 = a.tc >= 0 ? a.tc : a.t0s, tc = t1, t0s = t1, t0 = t1, tr = t1, td = t1;
                if (lp) {
                    t0 = lp.t0 >= 0 ? lp.t0 : (lp.tc >= 0 ? lp.tc : t1);
                    tc = lp.tc >= 0 ? Math.min(lp.tc, t0) : t0;
                    t0s = t0;
                    t1 = Math.max(t0, lp.tr);
                    tr = t1;
                    td = Math.max(lp.td, tr);
                }
                data = {src: c, dst: p, size: 0, tc: tc, t0s: t0s, t0: t0, t1: t1, tr: tr, td: td, ts: -1, rq: t1, rs: t1,
                        action: "", chunk: false, exact: false, tw: -1, kind: a.kind, idx: a.idx, missing: true};
            }
            edges.push({p: p, c: c, data: data, req: up ? f.answer : f.call, up: up});
            (children[p] = children[p] || []).push(c);
            parentRow[c] = data;
        }
        const rootList = Object.keys(nodes).filter(l => !hasParent[l]);
        if (rootList.length < 1 || rootList.length !== nodeCount - found.length)
            return;
        // layout: depth = level, x = position among the leaves; the tree must reach every node from the root
        const map = {};
        let leaf = 0, maxDepth = 0;
        const place = (loc, depth) => {
            maxDepth = Math.max(maxDepth, depth);
            const kids = (children[loc] || []).slice().sort((a, b) => a - b);
            let x;
            if (kids.length === 0) {
                x = leaf++;
            } else {
                let sum = 0;
                for (const k of kids)
                    sum += place(k, depth + 1);
                x = sum / kids.length;
            }
            map[loc] = {loc: loc, depth: depth, x: x, leaf: kids.length === 0};
            return x;
        };
        for (const rt of rootList.map(x => parseInt(x)).sort((a, b) => a - b))
            place(rt, 0);
        if (Object.keys(map).length !== nodeCount)
            return;
        treeNodeMap = map;
        treeNodes = Object.keys(map).map(k => map[k]);
        treeEdges = edges;
        treeLeaves = Math.max(leaf, 1);
        treeDepth = maxDepth;
        treeStart = g.start;
        treeUp = up;
        hasTree = true;

        // critical path: from the data message that arrives last, back over what each sender waited for
        let last = null, lastEnd = -Infinity;
        for (const e of edges) {
            const r = e.data, t = Math.max(r.t1, r.tr, r.td);
            if (t > lastEnd) { lastEnd = t; last = r; }
        }
        const segs = [], hops = [];
        const add = (kind, a, b, row) => {
            row.crit = true;
            if (b > a)
                segs.push({kind: kind, a: a, b: b});
        };
        let cur = last, final = true, guard = 0;
        while (cur && guard++ < 64) {
            hops.push(cur);
            if (final) {
                add("action", cur.tr, cur.td, cur);
                add("pick", cur.t1, cur.tr, cur);
                final = false;
            }
            add("mpi", cur.t0s, Math.max(cur.t0, cur.t1, cur.rq), cur);
            const created = cur.tc >= 0 ? cur.tc : cur.t0s;
            let from = null;                                  // what the sender had to wait for
            if (up) {
                // the data of the children: the last one that arrived before this parcel was created
                for (const e of edges)
                    if (e.p === cur.src && e.data.t1 <= created + 20 && (from === null || e.data.t1 > from.t1))
                        from = e.data;
                add("prepare", created, cur.t0s, cur);
                if (from) {
                    add("pick", from.t1, from.tr, from);
                    add("action", from.tr, Math.max(created, from.tr), from);    // combining the data of the children
                }
            } else {
                // down: the parcel for the children is created early and waits for the data of the parent
                from = parentRow[cur.src] || null;
                if (from && from.dst !== cur.src)
                    from = null;                              // the answer of the parent is missing (a parcel without MPI data)
                const edgeOfCur = edges.find(x => x.data === cur);
                const rqOfCur = edgeOfCur ? edgeOfCur.req : null;
                // the data cannot be prepared before the parent has its own data, or before the request of the child has arrived
                add("prepare", Math.max(created, from ? from.tr : (rqOfCur ? rqOfCur.tr : created)), cur.t0s, cur);
                if (from)
                    add("pick", from.t1, from.tr, from);
                else {
                    // a child of the root: its request and the wait of the request at the root
                    const rq = rqOfCur;
                    if (rq) {
                        add("parent", rq.tr, Math.max(created, rq.tr), rq);
                        add("pick", rq.t1, rq.tr, rq);
                        add("mpi", rq.t0s, Math.max(rq.t0, rq.t1, rq.rq), rq);
                        add("prepare", rq.tc >= 0 ? rq.tc : rq.t0s, rq.t0s, rq);
                    }
                }
            }
            cur = from;
        }
        let a0 = Infinity, prep = 0, mpi = 0, pick = 0, act = 0, par = 0;
        for (const sg of segs) {
            a0 = Math.min(a0, sg.a);
            if (sg.kind === "prepare") prep += sg.b - sg.a;
            else if (sg.kind === "mpi") mpi += sg.b - sg.a;
            else if (sg.kind === "pick") pick += sg.b - sg.a;
            else if (sg.kind === "parent") par += sg.b - sg.a;
            else act += sg.b - sg.a;
        }
        pathSegs = segs;
        pathLength = lastEnd - a0;
        pathStart = a0 - g.start;
        pathEnd = lastEnd - g.start;
        pathPrepare = prep;
        pathMpi = mpi;
        pathPick = pick;
        pathAction = act;
        pathParent = par;
        pathHops = hops.length;
        const names = hops.length > 0 ? [hops[hops.length - 1].src] : [];
        for (let i = hops.length - 1; i >= 0; --i)
            names.push(hops[i].dst);
        pathChain = names.map(l => "L#" + l).join(" → ");
    }

    function treeInfoText(e) {
        if (!e)
            return "Hover an edge: when the child asked, what it waited for, what HPX did and how long MPI took.";
        const d = e.data, q = e.req;
        const we = waitEnd(d);
        if (e.up)                                             // the data goes up in the call, the answer only confirms it
            return "L#" + e.c + " → L#" + e.p + ":  "
                + (d.tc >= 0 && we > d.tc ? "waited " + fmtUs(we - d.tc) + " for its children,  " : "")
                + "HPX prepared " + fmtUs(d.t0s - we) + ",  MPI " + fmtUs(Math.max(d.t0, d.t1, d.rq) - d.t0s)
                + ";  data arrived at +" + fmtUs(d.t1 - treeStart)
                + (q ? ";  confirmation of the parent at +" + fmtUs(q.tr - treeStart) : "");
        return "L#" + e.p + " → L#" + e.c + ":  "
            + (q ? "asked at +" + fmtUs(q.tc - treeStart) + " (request arrived after " + fmtUs(q.tr - q.tc) + "),  " : "")
            + (d.tc >= 0 && we > d.tc ? "waited " + fmtUs(we - d.tc) + " for the data of its parent,  " : "")
            + "HPX prepared " + fmtUs(d.t0s - we) + ",  MPI " + fmtUs(Math.max(d.t0, d.t1, d.rq) - d.t0s)
            + ";  data arrived at +" + fmtUs(d.t1 - treeStart);
    }

    function infoText(r) {
        if (!r)
            return "Move the mouse over a piece of work or an arrow. Two fingers scroll, pinch zooms (or Ctrl + wheel), drag moves.";
        return "L#" + r.src + " to L#" + r.dst + ", " + fmtSize(r.size) + ":  "
            + (r.tc >= 0 ? (waitEnd(r) > r.tc ? "waited " + fmtUs(waitEnd(r) - r.tc) + " for the data of its parent,  " : "")
                           + "HPX prepares " + fmtUs(r.t0s - waitEnd(r)) + ",  " : "")
            + "MPI send call " + fmtUs(r.t0 - r.t0s)
            + (r.rq > r.t0 ? ", send request completed after " + fmtUs(r.rq - r.t0s) + (r.exact ? "" : " (as HPX saw it)") : "")
            + ",  MPI receive complete " + fmtUs(r.t1 - r.t0s) + " after the send started"
            + (r.chunk ? "  (data of a large parcel)" : ",  HPX picks it up " + fmtUs(r.tr - r.t1))
            + (r.td >= 0 ? ",  action " + fmtUs(r.td - r.tr) : "")
            + (r.action ? "   [" + r.action.split("<")[0] + "]" : "");
    }

    RunFile {
        id: run
        onChanged: {
            if (loaded)
                hpxWindow.build();
            else {
                hpxWindow.groups = [];
                hpxWindow.select(0);
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: "Open a run file"
        nameFilters: ["EduHPX run file (*.csv)", "All files (*)"]
        onAccepted: run.load(selectedFile)
    }

    Dialog {
        id: aboutDialog
        title: "About EduHPX"
        modal: true
        anchors.centerIn: parent
        width: Math.min(560, hpxWindow.width - 40)
        standardButtons: Dialog.Close
        contentItem: Label {
            wrapMode: Text.WordWrap
            textFormat: Text.StyledText
            text: "<b>EduHPX</b> 0.1.0<br>HPX parcels and MPI messages on one timeline.<br><br>"
                + "Reads a run file (CSV, format 1) made by <i>eduhpx-merge</i>. Times are microseconds on the clock of the first node, -1 = unknown. "
                + "Green: MPI send, red: MPI receive, blue frame: MPI, striped: the send request is still open, grey: waiting for data.<br><br>"
                + "BSD-3-Clause. Uses Qt 6 (LGPL, dynamically linked)."
        }
    }

    // drop a run file on the window
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (drop) => { if (drop.hasUrls) hpxWindow.openFile(drop.urls[0]); }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Button {
                text: "Open run..."
                onClicked: fileDialog.open()
            }
            Button {
                text: "Start page"
                visible: run.loaded
                onClicked: run.unload()
            }
            Label {
                Layout.fillWidth: true
                color: run.error !== "" ? "#ff8a80" : "white"
                elide: Text.ElideRight
                text: run.error !== "" ? run.error
                    : run.loaded ? "Run " + run.name + " - " + hpxWindow.groups.length + " groups, " + run.messages.length + " parcels"
                                   + (hpxWindow.skipped > 0 ? " (" + hpxWindow.skipped + " without MPI data are not shown)" : "")
                    : ""
            }
        }

        // choose the group
        RowLayout {
            Layout.fillWidth: true
            visible: run.loaded && hpxWindow.groups.length > 0
            spacing: 10
            Button { text: "<"; enabled: hpxWindow.current > 0; onClicked: hpxWindow.select(hpxWindow.current - 1) }
            Label {
                color: "white"
                font.bold: true
                text: hpxWindow.groupLabel(hpxWindow.currentGroup)
            }
            Button { text: ">"; enabled: hpxWindow.current < hpxWindow.groups.length - 1; onClicked: hpxWindow.select(hpxWindow.current + 1) }
            Label {
                color: "white"
                text: hpxWindow.currentGroup
                    ? hpxWindow.rows.length + " messages, " + hpxWindow.fmtUs(hpxWindow.groupSpan) + " in total"
                    : ""
            }
            Item { Layout.fillWidth: true }
        }

        // what is in this group: how many messages, how much data, where the time goes
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: hpxWindow.showPath ? 150 : 124
            visible: run.loaded && hpxWindow.groups.length > 0
            color: "#3a3a3a"
            border.color: "#2b2b2b"
            radius: 3

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 22
                    Label { color: "white"; font.bold: true; text: hpxWindow.rows.length + " messages" }
                    Label { color: "white"; font.bold: true; text: hpxWindow.fmtSize(hpxWindow.sumBytes) + " data" }
                    Label { color: "white"; Layout.fillWidth: true; elide: Text.ElideRight
                            text: hpxWindow.senders + " of " + hpxWindow.localitiesInGroup + " localities send data, largest fan-out "
                                  + hpxWindow.maxFanOut + " (L#" + hpxWindow.fanOutLoc + ")" }
                    Label { color: "#999999"; text: "whole run: " + hpxWindow.runParcels + " messages, " + hpxWindow.fmtSize(hpxWindow.runBytes) }
                }
                // 1. the real time: the critical path of a broadcast, the chain that sets its length (percent of THIS time)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    visible: hpxWindow.showPath
                    Label { color: "#ffd600"; font.bold: true
                            text: "Critical path (wall clock) " + hpxWindow.fmtUs(hpxWindow.pathLength) + " of " + hpxWindow.fmtUs(hpxWindow.groupSpan) }
                    Label { color: "#bbbbbb"; Layout.fillWidth: true; elide: Text.ElideRight; text: hpxWindow.pathChain }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    visible: hpxWindow.showPath
                    readonly property real total: Math.max(hpxWindow.pathPrepare + hpxWindow.pathMpi + hpxWindow.pathPick + hpxWindow.pathParent + hpxWindow.pathAction, 1e-9)
                    Repeater {
                        model: [
                            {name: "HPX prepares", v: hpxWindow.pathPrepare, c: hpxWindow.preColor},
                            {name: "MPI", v: hpxWindow.pathMpi, c: hpxWindow.mpiColor},
                            {name: "HPX picks up", v: hpxWindow.pathPick, c: hpxWindow.recvColor},
                            {name: "request waits at parent", v: hpxWindow.pathParent, c: hpxWindow.parentColor},
                            {name: hpxWindow.treeUp ? "action + waiting for the other children" : "action", v: hpxWindow.pathAction, c: hpxWindow.actionColor}
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            property real before: {
                                let b = 0;
                                const parts = [hpxWindow.pathPrepare, hpxWindow.pathMpi, hpxWindow.pathPick, hpxWindow.pathParent, hpxWindow.pathAction];
                                for (let i = 0; i < index; ++i)
                                    b += parts[i];
                                return b;
                            }
                            x: parent.width * before / parent.total
                            width: Math.max(parent.width * modelData.v / parent.total, 0)
                            height: parent.height
                            color: modelData.c
                            Label {
                                anchors.centerIn: parent
                                color: "black"
                                font.pixelSize: 11
                                visible: parent.width > implicitWidth + 10
                                text: modelData.name + (modelData.name === "MPI" && hpxWindow.pathHops > 1 ? " (" + hpxWindow.pathHops + " hops)" : "") + " " + hpxWindow.fmtUs(modelData.v) + " (" + (100 * modelData.v / parent.parent.total).toFixed(0) + " %)"
                            }
                        }
                    }
                }
                // 2. the work of all messages added up: they overlap, so this is more than the real time
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18
                    Label { color: "#999999"; text: "Time of all messages added up (they run in parallel, so more than wall clock):" }
                    Label { color: hpxWindow.mpiColor; font.bold: true; text: "MPI " + hpxWindow.fmtUs(hpxWindow.sumMpi) }
                    Label { color: hpxWindow.recvColor; font.bold: true; text: "HPX " + hpxWindow.fmtUs(hpxWindow.sumHpx) }
                    Label { color: hpxWindow.waitColor; font.bold: true; visible: hpxWindow.sumWait > 0
                            text: "waiting for data " + hpxWindow.fmtUs(hpxWindow.sumWait) }
                    Label { color: hpxWindow.parentColor; font.bold: true; visible: hpxWindow.sumParent > 0
                            text: "requests wait at parent " + hpxWindow.fmtUs(hpxWindow.sumParent) }
                    Item { Layout.fillWidth: true }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: hpxWindow.showPath ? 8 : 24
                    readonly property real total: Math.max(hpxWindow.sumWait + hpxWindow.sumPre + hpxWindow.sumMpi + hpxWindow.sumPick + hpxWindow.sumParent + hpxWindow.sumAction, 1e-9)
                    Repeater {
                        model: [
                            {name: "waits for data", v: hpxWindow.sumWait, c: hpxWindow.waitColor},
                            {name: "HPX prepares", v: hpxWindow.sumPre, c: hpxWindow.preColor},
                            {name: "MPI", v: hpxWindow.sumMpi, c: hpxWindow.mpiColor},
                            {name: "HPX picks up", v: hpxWindow.sumPick, c: hpxWindow.recvColor},
                            {name: "request waits at parent", v: hpxWindow.sumParent, c: hpxWindow.parentColor},
                            {name: "action", v: hpxWindow.sumAction, c: hpxWindow.actionColor}
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            property real before: {
                                let b = 0;
                                const parts = [hpxWindow.sumWait, hpxWindow.sumPre, hpxWindow.sumMpi, hpxWindow.sumPick, hpxWindow.sumParent, hpxWindow.sumAction];
                                for (let i = 0; i < index; ++i)
                                    b += parts[i];
                                return b;
                            }
                            x: parent.width * before / parent.total
                            width: Math.max(parent.width * modelData.v / parent.total, 0)
                            height: parent.height
                            color: modelData.c
                            opacity: hpxWindow.showPath ? 0.7 : 1
                            Label {
                                anchors.centerIn: parent
                                color: "black"
                                font.pixelSize: 11
                                visible: parent.width > implicitWidth + 10 && !hpxWindow.showPath
                                text: modelData.name + " " + hpxWindow.fmtUs(modelData.v) + " (" + hpxWindow.pct(modelData.v) + ")"
                            }
                        }
                    }
                }
                // per message: the MPI time of a message is its whole life in MPI; the transfer is only the time on the wire
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18
                    visible: !hpxWindow.showPath && hpxWindow.rows.length > 0
                    Label { color: "#999999"; text: "per message:" }
                    Label { color: hpxWindow.mpiColor; font.bold: true
                            text: "MPI " + hpxWindow.fmtUs(hpxWindow.sumMpi / Math.max(hpxWindow.rows.length, 1))
                                  + " (transfer " + hpxWindow.fmtUs(hpxWindow.sumWire / Math.max(hpxWindow.rows.length, 1)) + ")" }
                    Label { color: hpxWindow.recvColor; font.bold: true
                            text: "HPX " + hpxWindow.fmtUs(hpxWindow.sumHpx / Math.max(hpxWindow.rows.length, 1)) }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        // all groups: one bar each; blue-grey = collective, grey = other traffic
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            visible: run.loaded && hpxWindow.groups.length > 0
            color: "#2b2b2b"
            border.color: "#222222"

            Canvas {
                id: strip
                anchors.fill: parent
                readonly property int pad: 8
                function barWidth() { return (width - 2 * pad) / Math.max(hpxWindow.groups.length, 1); }
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const n = hpxWindow.groups.length;
                    if (n === 0)
                        return;
                    let longest = 1;
                    for (const g of hpxWindow.groups)
                        longest = Math.max(longest, g.end - g.start);
                    const bw = barWidth();
                    for (let i = 0; i < n; ++i) {
                        const g = hpxWindow.groups[i];
                        const h = Math.max(3, Math.sqrt((g.end - g.start) / longest) * (height - 14));
                        ctx.fillStyle = i === hpxWindow.current ? "#ffffff" : (g.kind === "burst" ? "#6b6b6b" : "#6fa8dc");
                        ctx.fillRect(pad + i * bw + 1, height - 6 - h, Math.max(bw - 2, 1), h);
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    function pick(x) { hpxWindow.select(Math.floor((x - strip.pad) / strip.barWidth())); }
                    onPressed: (e) => pick(e.x)
                    onPositionChanged: (e) => { if (pressed) pick(e.x); }
                }
            }
        }

        // choose the view
        RowLayout {
            Layout.fillWidth: true
            visible: run.loaded && hpxWindow.groups.length > 0
            spacing: 4
            Button { text: "By locality"; checkable: true; checked: hpxWindow.viewMode === "locality"; onClicked: { hpxWindow.viewMode = "locality"; lanes.requestPaint(); } }
            Button { text: "By message"; checkable: true; checked: hpxWindow.viewMode === "message"; onClicked: { hpxWindow.viewMode = "message"; waterfall.requestPaint(); } }
            Button { text: "Tree"; visible: hpxWindow.hasTree; checkable: true; checked: hpxWindow.viewMode === "tree"; onClicked: { hpxWindow.viewMode = "tree"; tree.requestPaint(); } }
            Button { text: "Reset zoom"; onClicked: hpxWindow.select(hpxWindow.current) }
            Button {
                text: "Critical path"
                visible: hpxWindow.hasTree
                checkable: true
                checked: hpxWindow.criticalOn
                onToggled: { hpxWindow.criticalOn = checked; lanes.requestPaint(); waterfall.requestPaint(); tree.requestPaint(); }
            }
            Item { Layout.preferredWidth: 18 }
            Label { color: "#cccccc"; text: "Arrows:"; visible: hpxWindow.viewMode === "locality" && hpxWindow.hasDataClass }
            Repeater {
                model: hpxWindow.viewMode === "locality" && hpxWindow.hasDataClass ? [["all", "All"], ["data", "Data"], ["requests", hpxWindow.ackOnly ? "Confirmations" : "Requests"]] : []
                delegate: Button {
                    required property var modelData
                    text: modelData[1]
                    checkable: true
                    checked: hpxWindow.arrowFilter === modelData[0]
                    onClicked: { hpxWindow.arrowFilter = modelData[0]; lanes.requestPaint(); }
                }
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#2b2b2b"
            border.color: "#222222"
            clip: true

            // ---------------------------------------------------------------- view 1: one lane per locality
            Canvas {
                id: lanes
                anchors.fill: parent
                visible: hpxWindow.viewMode === "locality"
                readonly property int leftMargin: 80
                readonly property int topMargin: 24
                readonly property int rightMargin: 14
                readonly property int lanePad: 8
                property real trackH: 12

                function xOf(t) {
                    return leftMargin + (t - hpxWindow.viewStart) / (hpxWindow.viewEnd - hpxWindow.viewStart) * (width - leftMargin - rightMargin);
                }
                function tOf(x) {
                    return hpxWindow.viewStart + (x - leftMargin) / (width - leftMargin - rightMargin) * (hpxWindow.viewEnd - hpxWindow.viewStart);
                }
                function layout() {
                    const ls = hpxWindow.laneInfo;
                    let sum = 0;
                    for (const l of ls)
                        sum += l.tracks;
                    const avail = height - topMargin - 6 - ls.length * lanePad;
                    trackH = Math.max(9, Math.min(20, avail / Math.max(sum, 1)));
                    hpxWindow.contentH = topMargin + 6 + sum * trackH + ls.length * lanePad;
                    hpxWindow.scrollY = Math.max(0, Math.min(hpxWindow.scrollY, Math.max(hpxWindow.contentH - height, 0)));
                    let y = topMargin - hpxWindow.scrollY;
                    for (const l of ls) {
                        l.y0 = y;
                        l.h = l.tracks * trackH + lanePad;
                        y += l.h;
                    }
                }
                function laneOf(loc) {
                    for (const l of hpxWindow.laneInfo)
                        if (l.loc === loc)
                            return l;
                    return null;
                }
                function yOf(piece) {
                    const l = laneOf(piece.loc);
                    return l ? l.y0 + lanePad / 2 + piece.track * trackH + trackH / 2 : 0;
                }
                // the arrow starts at the end of the MPI send call, but never after the end of the receive
                // (big messages arrive while the sender is still in the call)
                function arrowStart(r) {
                    return Math.max(r.t0s, Math.min(r.t0, r.t1));
                }
                function arrow(ctx, x0, y0, x1, y1, w, color, outline) {
                    const ang = Math.atan2(y1 - y0, x1 - x0), h = 7 + w * 2.4;
                    const bx = x1 - h * 0.8 * Math.cos(ang), by = y1 - h * 0.8 * Math.sin(ang);   // the shaft ends inside the head
                    const head = () => {
                        ctx.beginPath();
                        ctx.moveTo(x1, y1);
                        ctx.lineTo(x1 - h * Math.cos(ang - 0.42), y1 - h * Math.sin(ang - 0.42));
                        ctx.lineTo(x1 - h * Math.cos(ang + 0.42), y1 - h * Math.sin(ang + 0.42));
                        ctx.closePath();
                    };
                    if (outline) {                       // dark halo under the line and the head
                        ctx.strokeStyle = "rgba(0,0,0,0.75)"; ctx.fillStyle = "rgba(0,0,0,0.75)"; ctx.lineWidth = w + 2.6;
                        ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(bx, by); ctx.stroke();
                        head(); ctx.lineWidth = 2.6; ctx.fill(); ctx.stroke();
                    }
                    ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = w;
                    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(bx, by); ctx.stroke();
                    head(); ctx.fill();
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onVisibleChanged: if (visible) requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    if (!visible || !run.loaded || hpxWindow.laneInfo.length === 0)
                        return;                                  // a hidden view must not touch the shared scroll state
                    layout();
                    const msgs = hpxWindow.laneMsgs;
                    const bh = trackH * 0.7;
                    const hot = hpxWindow.laneHover;

                    ctx.font = "12px sans-serif";
                    ctx.textAlign = "left";
                    hpxWindow.laneInfo.forEach((l, i) => {
                        ctx.fillStyle = i % 2 ? "#303030" : "#262626";
                        ctx.fillRect(0, l.y0, width, l.h);
                        ctx.fillStyle = "#dddddd";
                        ctx.fillText("L#" + l.loc, 10, l.y0 + Math.min(l.h, 30) / 2 + 4);
                    });

                    // time axis, 0 = start of this group
                    const origin = hpxWindow.currentGroup ? hpxWindow.currentGroup.start : 0;
                    const span = hpxWindow.viewEnd - hpxWindow.viewStart;
                    const raw = span / 8;
                    const pow10 = Math.pow(10, Math.floor(Math.log(Math.max(raw, 0.001)) / Math.LN10));
                    const step = [1, 2, 5, 10].map(f => f * pow10).find(s => s >= raw);
                    ctx.font = "11px sans-serif";
                    ctx.fillStyle = "#999999";
                    ctx.strokeStyle = "#3a3a3a";
                    ctx.lineWidth = 1;
                    let ticks = 0;
                    for (let t = Math.ceil((hpxWindow.viewStart - origin) / step) * step; t + origin <= hpxWindow.viewEnd && ticks < 40; t += step, ++ticks) {
                        const x = Math.round(xOf(t + origin)) + 0.5;
                        ctx.beginPath(); ctx.moveTo(x, topMargin - 4); ctx.lineTo(x, height); ctx.stroke();
                    }

                    // what each locality does: the send on the sender, the receive on the receiver
                    for (let i = 0; i < msgs.length; ++i) {
                        const m = msgs[i], r = m.row;
                        const yp = yOf(m.pre) - bh / 2, yr = yOf(m.rcv) - bh / 2;
                        if (r.tc >= 0) {                                       // sender: waits for the data of its parent, then HPX prepares the send
                            const we = hpxWindow.waitEnd(r);
                            if (we > r.tc) {
                                ctx.fillStyle = hpxWindow.waitColor;
                                ctx.fillRect(xOf(r.tc), yp, Math.max(xOf(we) - xOf(r.tc), 1.5), bh);
                            }
                            ctx.fillStyle = hpxWindow.preColor;
                            ctx.fillRect(xOf(we), yp, Math.max(xOf(r.t0s) - xOf(we), 1.5), bh);
                        }
                        const xs0 = xOf(r.t0s), xs1 = xOf(Math.max(r.t0, r.rq));
                        ctx.fillStyle = hpxWindow.mpiSendColor;                // sender: MPI send, the call itself (green)
                        ctx.fillRect(xs0, yp, Math.max(xOf(r.t0) - xs0, 2), bh);
                        if (r.rq > r.t0)                                       // sender: the send request is still open (striped)
                            hpxWindow.openRequest(ctx, xOf(r.t0), yp, Math.max(xOf(r.rq) - xOf(r.t0), 1.5), bh);
                        hpxWindow.mpiFrame(ctx, xs0, yp, Math.max(xs1 - xs0, 4), bh);
                        const xr0 = xOf(r.rs), xr1 = xOf(r.t1);
                        ctx.fillStyle = hpxWindow.mpiRecvColor;                // receiver: MPI receive until it is complete (red)
                        ctx.fillRect(xr0, yr, Math.max(xr1 - xr0, 2), bh);
                        hpxWindow.mpiFrame(ctx, xr0, yr, Math.max(xr1 - xr0, 4), bh);
                        if (r.tr > r.t1) {                                     // receiver: HPX picks it up
                            ctx.fillStyle = hpxWindow.recvColor;
                            ctx.fillRect(xOf(r.t1), yr, Math.max(xOf(r.tr) - xOf(r.t1), 1.5), bh);
                        }
                        if (r.td > r.tr) {                                     // receiver: the action runs
                            ctx.fillStyle = hpxWindow.isRequestWait(r) ? hpxWindow.parentColor : hpxWindow.actionColor;
                            ctx.fillRect(xOf(r.tr), yr, Math.max(xOf(r.td) - xOf(r.tr), 1.5), bh);
                        }
                        if (r.chunk && r.tr < r.t1) {                          // large parcel: HPX saw the header earlier
                            ctx.fillStyle = hpxWindow.recvColor;
                            ctx.beginPath();
                            ctx.moveTo(xOf(r.tr), yr); ctx.lineTo(xOf(r.tr) + 3, yr + bh / 2);
                            ctx.lineTo(xOf(r.tr), yr + bh); ctx.lineTo(xOf(r.tr) - 3, yr + bh / 2);
                            ctx.closePath(); ctx.fill();
                        }
                    }
                    // arrows on top of the bars: thin, with a dark outline so that they can be followed over any colour;
                    // the one under the mouse is highlighted
                    const dense = msgs.length > 30;
                    const crit = hpxWindow.criticalOn && hpxWindow.hasTree;
                    for (let i = 0; i < msgs.length; ++i) {
                        if (i === hot || !hpxWindow.arrowShown(msgs[i].row))
                            continue;
                        const m = msgs[i], r = m.row;
                        if (crit && r.crit)
                            continue;                                          // the critical path is drawn last, on top
                        arrow(ctx, xOf(arrowStart(r)), yOf(m.pre), xOf(r.t1), yOf(m.rcv), dense ? 0.9 : 1.3,
                              crit ? "rgba(240,240,240,0.28)" : (dense ? "rgba(240,240,240,0.55)" : "rgba(255,255,255,0.95)"), true);
                    }
                    if (crit) {
                        for (let i = 0; i < msgs.length; ++i) {
                            const m = msgs[i], r = m.row;
                            if (!r.crit || i === hot)
                                continue;
                            arrow(ctx, xOf(arrowStart(r)), yOf(m.pre), xOf(r.t1), yOf(m.rcv), 3, "#ffd600", true);
                            ctx.strokeStyle = "#ffd600"; ctx.lineWidth = 2;
                            ctx.strokeRect(xOf(m.pre.a), yOf(m.pre) - bh / 2, Math.max(xOf(m.pre.b) - xOf(m.pre.a), 2), bh);
                            ctx.strokeRect(xOf(m.rcv.a), yOf(m.rcv) - bh / 2, Math.max(xOf(m.rcv.b) - xOf(m.rcv.a), 3), bh);
                        }
                    }
                    if (hot >= 0 && hot < msgs.length) {
                        const m = msgs[hot], r = m.row;
                        arrow(ctx, xOf(arrowStart(r)), yOf(m.pre), xOf(r.t1), yOf(m.rcv), 2.2, "#ff4081", true);
                        ctx.strokeStyle = "#ff4081"; ctx.lineWidth = 1.5;
                        ctx.strokeRect(xOf(m.pre.a), yOf(m.pre) - bh / 2, Math.max(xOf(m.pre.b) - xOf(m.pre.a), 2), bh);
                        ctx.strokeRect(xOf(m.rcv.a), yOf(m.rcv) - bh / 2, Math.max(xOf(m.rcv.b) - xOf(m.rcv.a), 3), bh);
                    }
                    // the time axis stays on top while the lanes scroll under it
                    ctx.fillStyle = "#2b2b2b";
                    ctx.fillRect(0, 0, width, topMargin - 4);
                    ctx.font = "11px sans-serif";
                    ctx.fillStyle = "#999999";
                    for (let t = Math.ceil((hpxWindow.viewStart - origin) / step) * step, n = 0; t + origin <= hpxWindow.viewEnd && n < 40; t += step, ++n)
                        ctx.fillText(hpxWindow.fmtUs(t), Math.round(xOf(t + origin)) + 3.5, 13);
                }

                PinchHandler {
                    target: null
                    property real last: 1
                    onActiveChanged: last = 1
                    onActiveScaleChanged: {
                        const f = last / activeScale;
                        last = activeScale;
                        const tc = lanes.tOf(centroid.position.x);
                        hpxWindow.setView(tc - (tc - hpxWindow.viewStart) * f, tc + (hpxWindow.viewEnd - tc) * f);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    property real pressX: 0
                    property real startAt: 0
                    property real endAt: 0
                    function distToSegment(px, py, x0, y0, x1, y1) {
                        const dx = x1 - x0, dy = y1 - y0, len2 = dx * dx + dy * dy;
                        let u = len2 > 0 ? ((px - x0) * dx + (py - y0) * dy) / len2 : 0;
                        u = Math.max(0, Math.min(1, u));
                        return Math.hypot(px - (x0 + u * dx), py - (y0 + u * dy));
                    }
                    onPressed: (e) => { pressX = e.x; startAt = hpxWindow.viewStart; endAt = hpxWindow.viewEnd; }
                    onWheel: (w) => {
                        if (w.modifiers & Qt.ControlModifier) {            // Ctrl + wheel zooms the time axis
                            const factor = w.angleDelta.y > 0 ? 0.8 : 1.25;
                            const tc = lanes.tOf(w.x);
                            hpxWindow.setView(tc - (tc - hpxWindow.viewStart) * factor, tc + (hpxWindow.viewEnd - tc) * factor);
                            return;
                        }
                        if (w.angleDelta.x !== 0) {                         // sideways: move in time
                            const dt = -w.angleDelta.x / 4 / (lanes.width - lanes.leftMargin - lanes.rightMargin) * (hpxWindow.viewEnd - hpxWindow.viewStart);
                            hpxWindow.setView(hpxWindow.viewStart + dt, hpxWindow.viewEnd + dt);
                        }
                        if (w.angleDelta.y !== 0) {                         // up / down: scroll the rows
                            hpxWindow.scrollBy(-w.angleDelta.y / 2, lanes.height);
                            lanes.requestPaint();
                        }
                    }
                    onPositionChanged: (e) => {
                        if (pressed) {
                            const dt = (e.x - pressX) / (lanes.width - lanes.leftMargin - lanes.rightMargin) * (endAt - startAt);
                            hpxWindow.setView(startAt - dt, startAt - dt + (endAt - startAt));
                            return;
                        }
                        let best = -1, bestDist = 6;
                        const th = lanes.trackH * 0.7 / 2 + 2;
                        hpxWindow.laneMsgs.forEach((m, i) => {
                            const r = m.row;
                            let d = hpxWindow.arrowShown(r)
                                ? distToSegment(e.x, e.y, lanes.xOf(lanes.arrowStart(r)), lanes.yOf(m.pre), lanes.xOf(r.t1), lanes.yOf(m.rcv)) : 1e9;
                            if (Math.abs(e.y - lanes.yOf(m.pre)) <= th && e.x >= lanes.xOf(m.pre.a) - 2 && e.x <= lanes.xOf(m.pre.b) + 2)
                                d = 0;
                            if (Math.abs(e.y - lanes.yOf(m.rcv)) <= th && e.x >= lanes.xOf(m.rcv.a) - 3 && e.x <= lanes.xOf(m.rcv.b) + 3)
                                d = 0;
                            if (d < bestDist) { bestDist = d; best = i; }
                        });
                        if (best !== hpxWindow.laneHover) {
                            hpxWindow.laneHover = best;
                            lanes.requestPaint();
                        }
                    }
                }
            }

            // ---------------------------------------------------------------- view 3: the tree of a broadcast
            Canvas {
                id: tree
                anchors.fill: parent
                visible: hpxWindow.viewMode === "tree"
                readonly property int padX: 120
                readonly property int padTop: 56
                // many localities: the tree adapts to the room it has. sp = horizontal room per leaf; below 100 px the labels would
                // run into each other, so the nodes and arrows shrink, the leaves alternate between two heights, and the
                // times of an edge are only written for the edge under the mouse
                readonly property real sp: (width - 2 * padX) / Math.max(hpxWindow.treeLeaves - 1, 1)
                readonly property bool compact: sp < 100
                readonly property real sc: Math.max(0.45, Math.min(1, sp / 100))
                readonly property real nodeR: Math.max(8, 17 * sc)
                readonly property real stagger: compact ? Math.max(26, 44 * sc) : 0
                readonly property int padBottom: compact ? 110 : 70
                function nx(n) { return padX + (width - 2 * padX) * (hpxWindow.treeLeaves > 1 ? n.x / (hpxWindow.treeLeaves - 1) : 0.5); }
                function ny(n) {
                    return padTop + (height - padTop - padBottom) * (hpxWindow.treeDepth > 0 ? n.depth / hpxWindow.treeDepth : 0)
                           + (compact && n.leaf ? (Math.round(n.x) % 2) * stagger : 0);
                }
                function label(ctx, text, x, y, align, color) {
                    ctx.textAlign = align;
                    const w = ctx.measureText(text).width;
                    const left = align === "right" ? x - w : (align === "center" ? x - w / 2 : x);
                    ctx.fillStyle = "rgba(43,43,43,0.88)";
                    ctx.fillRect(left - 2, y - 10, w + 4, 14);
                    ctx.fillStyle = color;
                    ctx.fillText(text, x, y);
                }
                // arrow: the head grows with the width of the line and the shaft ends inside the head (a shaft that runs to the
                // tip pokes out in front of the head)
                function arrowHead(ctx, x0, y0, x1, y1, w, color) {
                    const ang = Math.atan2(y1 - y0, x1 - x0), h = 8 * sc + w * 2.6;
                    const bx = x1 - h * 0.8 * Math.cos(ang), by = y1 - h * 0.8 * Math.sin(ang);
                    ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = w;
                    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(bx, by); ctx.stroke();
                    ctx.beginPath(); ctx.moveTo(x1, y1);
                    ctx.lineTo(x1 - h * Math.cos(ang - 0.42), y1 - h * Math.sin(ang - 0.42));
                    ctx.lineTo(x1 - h * Math.cos(ang + 0.42), y1 - h * Math.sin(ang + 0.42));
                    ctx.closePath(); ctx.fill();
                }
                // the two lines of an edge, next to each other: data from the parent to the child, request the other way
                function edgeGeometry(e) {
                    const pn = hpxWindow.treeNodeMap[e.p], cn = hpxWindow.treeNodeMap[e.c];
                    const x0 = nx(pn), y0 = ny(pn), x1 = nx(cn), y1 = ny(cn);
                    const len = Math.max(Math.hypot(x1 - x0, y1 - y0), 1);
                    const ox = -(y1 - y0) / len * 5 * sc, oy = (x1 - x0) / len * 5 * sc;
                    const r = nodeR + 1, ux = (x1 - x0) / len, uy = (y1 - y0) / len;
                    return {dx0: x0 + ux * r + ox, dy0: y0 + uy * r + oy, dx1: x1 - ux * (r + 4) + ox, dy1: y1 - uy * (r + 4) + oy,
                            qx0: x1 - ux * r - ox, qy0: y1 - uy * r - oy, qx1: x0 + ux * (r + 4) - ox, qy1: y0 + uy * (r + 4) - oy,
                            mx: (x0 + x1) / 2, my: (y0 + y1) / 2};
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    if (!run.loaded || !hpxWindow.hasTree)
                        return;
                    const crit = hpxWindow.criticalOn;
                    ctx.font = "11px sans-serif";
                    ctx.textAlign = "center";
                    for (let i = 0; i < hpxWindow.treeEdges.length; ++i) {
                        const e = hpxWindow.treeEdges[i], g = edgeGeometry(e);
                        const hot = i === hpxWindow.treeHover;
                        const onPath = crit && e.data.crit;
                        const dataColor = hot ? "#ff4081" : (onPath ? "#ffd600" : (crit ? "rgba(255,255,255,0.3)" : "#ffffff"));
                        const reqColor = hot ? "#ff4081" : (onPath ? "#ffd600" : (crit ? "rgba(255,183,77,0.3)" : "#ffb74d"));
                        const wData = Math.max((2 + Math.min(Math.sqrt(e.data.size) / 150, 2)) * sc, 1) + (onPath || hot ? 1 : 0);
                        const wReq = Math.max(1.2 * sc, 0.8) + (onPath || hot ? 1 : 0);
                        if (e.up) {                                    // the data moves up: it uses the line from the child to the parent
                            arrowHead(ctx, g.qx0, g.qy0, g.qx1, g.qy1, wData, dataColor);
                            if (e.req)
                                arrowHead(ctx, g.dx0, g.dy0, g.dx1, g.dy1, wReq, reqColor);
                        } else {
                            arrowHead(ctx, g.dx0, g.dy0, g.dx1, g.dy1, wData, dataColor);
                            if (e.req)
                                arrowHead(ctx, g.qx0, g.qy0, g.qx1, g.qy1, wReq, reqColor);
                        }
                        // the time this hop took: from the arrival at the parent (or the request, at the root) to the arrival here
                        const up = hpxWindow.treeNodeMap[e.p] ? e.data : null;
                        let from = e.req ? e.req.tc : hpxWindow.treeStart;
                        for (const o of hpxWindow.treeEdges)
                            if (o.c === e.p)
                                from = o.data.t1;
                        if (e.up)                                      // data moving up: from the parcel created to its arrival
                            from = e.data.tc >= 0 ? e.data.tc : e.data.t0s;
                        // 62 % along the edge, so that the labels of many edges that start in one node do not run into each other
                        if (!compact || hot)
                            label(ctx, "+" + hpxWindow.fmtUs(e.data.t1 - from), g.dx0 + (g.dx1 - g.dx0) * 0.62 + 14, g.dy0 + (g.dy1 - g.dy0) * 0.62 + 4,
                                  "left", "#dddddd");
                    }
                    for (const n of hpxWindow.treeNodes) {
                        const x = nx(n), y = ny(n);
                        let arrive = null;
                        for (const e of hpxWindow.treeEdges) {
                            if (hpxWindow.treeUp) {                    // up: when the node had the data of all its children
                                if (e.p === n.loc)
                                    arrive = Math.max(arrive === null ? -Infinity : arrive, e.data.t1 - hpxWindow.treeStart);
                            } else if (e.c === n.loc) {
                                arrive = e.data.t1 - hpxWindow.treeStart;
                            }
                        }
                        const isRoot = n.depth === 0;
                        const onPath = crit && hpxWindow.pathChain.indexOf("L#" + n.loc + " ") >= 0 || (crit && hpxWindow.pathChain.endsWith("L#" + n.loc));
                        ctx.fillStyle = "#2f2f2f";
                        ctx.beginPath(); ctx.arc(x, y, nodeR, 0, 2 * Math.PI); ctx.fill();
                        ctx.strokeStyle = onPath ? "#ffd600" : "#cccccc"; ctx.lineWidth = onPath ? 3 : 1.5;
                        ctx.beginPath(); ctx.arc(x, y, nodeR, 0, 2 * Math.PI); ctx.stroke();
                        ctx.fillStyle = "#ffffff";
                        ctx.textAlign = "center";                  // label() leaves its own alignment set
                        if (nodeR >= 15) {
                            ctx.font = "bold 11px sans-serif";
                            ctx.fillText("L#" + n.loc, x, y + 4);
                        } else {                                   // small node: only the number
                            ctx.font = "bold " + Math.round(nodeR * 1.0) + "px sans-serif";
                            ctx.fillText(String(n.loc), x, y + nodeR * 0.35);
                        }
                        ctx.font = "10px sans-serif";
                        let hotChild = false;
                        if (hpxWindow.treeHover >= 0)
                            hotChild = hpxWindow.treeEdges[hpxWindow.treeHover].c === n.loc;
                        if (!compact)
                            // to the left of the node: the edges to the parent and to the children leave it above and below
                            { if (hpxWindow.treeUp) { if (arrive !== null) label(ctx, (isRoot ? "root, " : "") + "all data +" + hpxWindow.fmtUs(arrive), x - nodeR - 7, y + 4, "right", "#bbbbbb");
                                                      else if (isRoot) label(ctx, "root", x - nodeR - 7, y + 4, "right", "#bbbbbb"); }
                              else label(ctx, arrive === null ? "root" : "data +" + hpxWindow.fmtUs(arrive), x - nodeR - 7, y + 4, "right", "#bbbbbb"); }
                        else if (hotChild && arrive !== null)
                            label(ctx, "data +" + hpxWindow.fmtUs(arrive), x, y + nodeR + 14, "center", "#ffffff");
                        else if (isRoot)
                            label(ctx, "root", x - nodeR - 6, y + 4, "right", "#bbbbbb");
                    }
                    ctx.textAlign = "left";
                    ctx.fillStyle = "#999999";
                    ctx.font = "11px sans-serif";
                    ctx.fillText((hpxWindow.treeUp ? "white: data to the parent   orange: the message back   +t: time of the hop   all data +t: the node had the data of all its children" : "white: data from the parent   orange: request to the parent   +t: time of the hop   data +t: arrival after the start of the group")
                                 + (compact ? "   (many localities: hover an edge for its times)" : ""), 14, height - 14);
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: (e) => {
                        let best = -1, bestDist = 9;
                        hpxWindow.treeEdges.forEach((ed, i) => {
                            const g = tree.edgeGeometry(ed);
                            const dx = g.dx1 - g.dx0, dy = g.dy1 - g.dy0, len2 = dx * dx + dy * dy;
                            let u = len2 > 0 ? ((e.x - g.dx0) * dx + (e.y - g.dy0) * dy) / len2 : 0;
                            u = Math.max(0, Math.min(1, u));
                            const d = Math.hypot(e.x - (g.dx0 + u * dx), e.y - (g.dy0 + u * dy));
                            if (d < bestDist) { bestDist = d; best = i; }
                        });
                        if (best !== hpxWindow.treeHover) {
                            hpxWindow.treeHover = best;
                            tree.requestPaint();
                        }
                    }
                }
            }

            // ---------------------------------------------------------------- view 2: one row per message
            Canvas {
                id: waterfall
                anchors.fill: parent
                visible: hpxWindow.viewMode === "message"
                readonly property int leftMargin: 190
                readonly property int topMargin: 24
                readonly property int rightMargin: 12

                function rowHeight() {
                    return Math.max(12, Math.min(34, (height - topMargin - 6) / Math.max(hpxWindow.rows.length, 1)));
                }
                function xOf(t) {
                    return leftMargin + (t - hpxWindow.viewStart) / (hpxWindow.viewEnd - hpxWindow.viewStart) * (width - leftMargin - rightMargin);
                }
                function tOf(x) {
                    return hpxWindow.viewStart + (x - leftMargin) / (width - leftMargin - rightMargin) * (hpxWindow.viewEnd - hpxWindow.viewStart);
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onVisibleChanged: if (visible) requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    if (!visible || !run.loaded)
                        return;                                  // a hidden view must not touch the shared scroll state
                    const rows = hpxWindow.rows;
                    const rh = rowHeight();
                    hpxWindow.contentH = topMargin + 6 + rows.length * rh;
                    hpxWindow.scrollY = Math.max(0, Math.min(hpxWindow.scrollY, Math.max(hpxWindow.contentH - height, 0)));
                    const origin = hpxWindow.currentGroup ? hpxWindow.currentGroup.start : 0;
                    const span = hpxWindow.viewEnd - hpxWindow.viewStart;
                    const raw = span / 8;
                    const pow10 = Math.pow(10, Math.floor(Math.log(Math.max(raw, 0.001)) / Math.LN10));
                    const step = [1, 2, 5, 10].map(f => f * pow10).find(s => s >= raw);
                    ctx.font = "11px sans-serif";
                    ctx.textAlign = "left";
                    ctx.fillStyle = "#999999";
                    ctx.strokeStyle = "#3a3a3a";
                    ctx.lineWidth = 1;
                    let ticks = 0;
                    for (let t = Math.ceil((hpxWindow.viewStart - origin) / step) * step; t + origin <= hpxWindow.viewEnd && ticks < 40; t += step, ++ticks) {
                        const x = Math.round(xOf(t + origin)) + 0.5;
                        ctx.beginPath(); ctx.moveTo(x, topMargin - 4); ctx.lineTo(x, height); ctx.stroke();
                    }

                    const bar = Math.max(rh * 0.6, 2);
                    for (let i = 0; i < rows.length; ++i) {
                        const r = rows[i];
                        const y = topMargin + i * rh - hpxWindow.scrollY, mid = y + rh / 2;
                        if (y + rh < topMargin || y > height)
                            continue;
                        if (i === hpxWindow.hoverIndex) {
                            ctx.fillStyle = "rgba(255,255,255,0.10)";
                            ctx.fillRect(0, y, width, rh);
                        }
                        if (rh >= 11) {         // labels only if there is room for them
                            ctx.fillStyle = "#dddddd";
                            ctx.font = "11px sans-serif";
                            ctx.fillText("L#" + r.src + " > L#" + r.dst + "  " + hpxWindow.fmtSize(r.size) + "  " + hpxWindow.actionTag(r.action), 8, mid + 4);
                        }
                        if (r.tc >= 0) {
                            const we = hpxWindow.waitEnd(r);
                            if (we > r.tc) {
                                ctx.fillStyle = hpxWindow.waitColor;
                                ctx.fillRect(xOf(r.tc), mid - bar / 2, Math.max(xOf(we) - xOf(r.tc), 1.5), bar);
                            }
                            ctx.fillStyle = hpxWindow.preColor;
                            ctx.fillRect(xOf(we), mid - bar / 2, Math.max(xOf(r.t0s) - xOf(we), 1.5), bar);
                        }
                        // one MPI box: send on top (green, light green while the request is open), receive below (red)
                        const top = mid - bar / 2, half = bar / 2;
                        const boxL = xOf(Math.min(r.t0s, r.rs)), boxR = xOf(Math.max(r.t0, r.rq, r.t1));
                        ctx.fillStyle = hpxWindow.mpiSendColor;
                        ctx.fillRect(xOf(r.t0s), top, Math.max(xOf(r.t0) - xOf(r.t0s), 2), half);
                        if (r.rq > r.t0)
                            hpxWindow.openRequest(ctx, xOf(r.t0), top, Math.max(xOf(r.rq) - xOf(r.t0), 1.5), half);
                        ctx.fillStyle = hpxWindow.mpiRecvColor;
                        ctx.fillRect(xOf(r.rs), top + half, Math.max(xOf(r.t1) - xOf(r.rs), 2), half);
                        hpxWindow.mpiFrame(ctx, boxL, top, Math.max(boxR - boxL, 4), bar);
                        if (r.tr > r.t1) {
                            ctx.fillStyle = hpxWindow.recvColor;
                            ctx.fillRect(xOf(r.t1), mid - bar / 2, Math.max(xOf(r.tr) - xOf(r.t1), 1.5), bar);
                        }
                        if (r.td > r.tr) {
                            ctx.fillStyle = hpxWindow.isRequestWait(r) ? hpxWindow.parentColor : hpxWindow.actionColor;
                            ctx.fillRect(xOf(r.tr), mid - bar / 2, Math.max(xOf(r.td) - xOf(r.tr), 1.5), bar);
                        }
                        if (r.ts >= 0) {
                            ctx.fillStyle = "#ffffff";
                            ctx.fillRect(xOf(r.ts) - 0.5, mid - bar / 2 - 2, 1.5, bar + 4);
                        }
                        if (hpxWindow.criticalOn && r.crit) {                  // on the critical path: gold marker and outline
                            ctx.fillStyle = "#ffd600";
                            ctx.fillRect(0, y + 1, 5, Math.max(rh - 2, 2));
                            ctx.strokeStyle = "#ffd600"; ctx.lineWidth = 1.2;
                            ctx.strokeRect(xOf(Math.min(r.tc >= 0 ? r.tc : r.t0s, r.t0s)) - 1, mid - bar / 2 - 1,
                                           Math.max(xOf(Math.max(r.t1, r.tr, r.td)) - xOf(Math.min(r.tc >= 0 ? r.tc : r.t0s, r.t0s)) + 2, 4), bar + 2);
                        }
                    }
                    ctx.fillStyle = "#2b2b2b";
                    ctx.fillRect(0, 0, width, topMargin - 4);
                    ctx.font = "11px sans-serif";
                    ctx.fillStyle = "#999999";
                    for (let t = Math.ceil((hpxWindow.viewStart - origin) / step) * step, n = 0; t + origin <= hpxWindow.viewEnd && n < 40; t += step, ++n)
                        ctx.fillText(hpxWindow.fmtUs(t), Math.round(xOf(t + origin)) + 3.5, 13);
                }

                PinchHandler {
                    target: null
                    property real last: 1
                    onActiveChanged: last = 1
                    onActiveScaleChanged: {
                        const f = last / activeScale;
                        last = activeScale;
                        const tc = waterfall.tOf(centroid.position.x);
                        hpxWindow.setView(tc - (tc - hpxWindow.viewStart) * f, tc + (hpxWindow.viewEnd - tc) * f);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    property real pressX: 0
                    property real startAt: 0
                    property real endAt: 0
                    onPressed: (e) => { pressX = e.x; startAt = hpxWindow.viewStart; endAt = hpxWindow.viewEnd; }
                    onWheel: (w) => {
                        if (w.modifiers & Qt.ControlModifier) {            // Ctrl + wheel zooms the time axis
                            const factor = w.angleDelta.y > 0 ? 0.8 : 1.25;
                            const tc = waterfall.tOf(w.x);
                            hpxWindow.setView(tc - (tc - hpxWindow.viewStart) * factor, tc + (hpxWindow.viewEnd - tc) * factor);
                            return;
                        }
                        if (w.angleDelta.x !== 0) {                         // sideways: move in time
                            const dt = -w.angleDelta.x / 4 / (waterfall.width - waterfall.leftMargin - waterfall.rightMargin) * (hpxWindow.viewEnd - hpxWindow.viewStart);
                            hpxWindow.setView(hpxWindow.viewStart + dt, hpxWindow.viewEnd + dt);
                        }
                        if (w.angleDelta.y !== 0) {                         // up / down: scroll the rows
                            hpxWindow.scrollBy(-w.angleDelta.y / 2, waterfall.height);
                            waterfall.requestPaint();
                        }
                    }
                    onPositionChanged: (e) => {
                        if (pressed) {
                            const dt = (e.x - pressX) / (waterfall.width - waterfall.leftMargin - waterfall.rightMargin) * (endAt - startAt);
                            hpxWindow.setView(startAt - dt, startAt - dt + (endAt - startAt));
                            return;
                        }
                        const i = Math.floor((e.y - waterfall.topMargin + hpxWindow.scrollY) / waterfall.rowHeight());
                        const n = i >= 0 && i < hpxWindow.rows.length ? i : -1;
                        if (n !== hpxWindow.hoverIndex) {
                            hpxWindow.hoverIndex = n;
                            waterfall.requestPaint();
                        }
                    }
                }
            }

            // vertical scrolling when there are more lanes / messages than fit
            ScrollBar {
                id: vbar
                orientation: Qt.Vertical
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 24
                visible: (hpxWindow.viewMode === "locality" || hpxWindow.viewMode === "message") && hpxWindow.contentH > parent.height + 1
                policy: ScrollBar.AlwaysOn
                size: parent.height / Math.max(hpxWindow.contentH, 1)
                // not bound to scrollY (that would be a binding loop with the handler below): synced by hand
                function sync() {
                    if (!pressed)
                        position = hpxWindow.contentH > 0 ? hpxWindow.scrollY / hpxWindow.contentH : 0;
                }
                Connections {
                    target: hpxWindow
                    function onScrollYChanged() { vbar.sync(); }
                    function onContentHChanged() { vbar.sync(); }
                }
                onPositionChanged: {
                    if (pressed) {
                        hpxWindow.scrollY = Math.max(0, Math.min(position * hpxWindow.contentH, hpxWindow.contentH - parent.height));
                        lanes.requestPaint();
                        waterfall.requestPaint();
                    }
                }
            }
        }

        // legend (wraps in a narrow window) and the details of what is under the mouse
        Flow {
            Layout.fillWidth: true
            visible: run.loaded
            spacing: 12
            Row { spacing: 5; Rectangle { width: 20; height: 10; color: hpxWindow.waitColor; anchors.verticalCenter: parent.verticalCenter } Label { color: "white"; text: "waits for data" } }
            Row { spacing: 5; Rectangle { width: 20; height: 10; color: hpxWindow.preColor; anchors.verticalCenter: parent.verticalCenter } Label { color: "white"; text: "HPX prepares" } }
            Row { spacing: 5; Rectangle { width: 20; height: 10; color: hpxWindow.mpiSendColor; border.color: hpxWindow.mpiColor; border.width: 1.5; anchors.verticalCenter: parent.verticalCenter } Label { color: "white"; text: "MPI send" } }
            Row { spacing: 5
                Canvas {
                    width: 20; height: 10
                    anchors.verticalCenter: parent.verticalCenter
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        hpxWindow.openRequest(ctx, 0, 0, 20, 10);
                        hpxWindow.mpiFrame(ctx, 0, 0, 20, 10);
                    }
                }
                Label { color: "white"; text: "send open" }
            }
            Row { spacing: 5; Rectangle { width: 20; height: 10; color: hpxWindow.mpiRecvColor; border.color: hpxWindow.mpiColor; border.width: 1.5; anchors.verticalCenter: parent.verticalCenter } Label { color: "white"; text: "MPI receive" } }
            Row { spacing: 5; Rectangle { width: 20; height: 10; color: hpxWindow.recvColor; anchors.verticalCenter: parent.verticalCenter } Label { color: "white"; text: "HPX picks up" } }
            Row { spacing: 5; Rectangle { width: 20; height: 10; color: hpxWindow.actionColor; anchors.verticalCenter: parent.verticalCenter } Label { color: "white"; text: hpxWindow.criticalOn && hpxWindow.hasTree && hpxWindow.treeUp ? "action runs (on the path: incl. waiting for the other children)" : "action runs" } }
            Row { spacing: 5; visible: hpxWindow.sumParent > 0; Rectangle { width: 20; height: 10; color: hpxWindow.parentColor; anchors.verticalCenter: parent.verticalCenter } Label { color: "white"; text: "request waits at parent" } }
            Row { spacing: 5; Rectangle { width: 2; height: 14; color: "white" } Label { color: "white"; text: "send noticed by HPX" } }
            Row { spacing: 5; visible: hpxWindow.viewMode === "locality"; Label { color: hpxWindow.recvColor; font.bold: true; text: "\u25C6" } Label { color: "white"; text: "HPX saw the header of a large message" } }
            Label { color: hpxWindow.mpiColor; font.bold: true; text: "→ data (blue frame = MPI)"; visible: hpxWindow.viewMode === "locality" }
            Label { color: "#ffd600"; font.bold: true; text: "gold = critical path"; visible: hpxWindow.criticalOn && hpxWindow.hasTree }
        }
        Label {
            Layout.fillWidth: true
            visible: run.loaded
            color: "#dddddd"
            elide: Text.ElideRight
            text: {
                if (hpxWindow.viewMode === "tree")
                    return hpxWindow.treeInfoText(hpxWindow.treeHover >= 0 ? hpxWindow.treeEdges[hpxWindow.treeHover] : null);
                const lm = hpxWindow.laneHover >= 0 ? hpxWindow.laneMsgs[hpxWindow.laneHover] : undefined;
                const r = hpxWindow.viewMode === "locality"
                    ? (lm ? lm.row : null)
                    : (hpxWindow.hoverIndex >= 0 ? hpxWindow.rows[hpxWindow.hoverIndex] : null);
                return hpxWindow.infoText(r ? r : null);
            }
        }
    }

    // start screen: the logo, open a file, and the examples that are built in (in their own frame)
    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 84          // below the bar with the Open button, inside the dark area
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.bottomMargin: 16
        visible: !run.loaded
        spacing: 12
        Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: Math.max(100, Math.min(180, hpxWindow.height * 0.22))
            Layout.preferredWidth: Layout.preferredHeight * sourceSize.width / Math.max(1, sourceSize.height)
            source: "qrc:/qt/qml/EduHPX/assets/logo.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14
            Label { color: "#cccccc"; text: "Open a run file (.csv) or drop it here" }
            Button { text: "Open run file..."; onClicked: fileDialog.open() }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: 980
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            color: "#363636"
            border.color: "#5a5a5a"
            radius: 4
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label { color: "white"; font.bold: true; font.pixelSize: 20; text: "Examples" }
                    Label { Layout.fillWidth: true; color: "#aaaaaa"; elide: Text.ElideRight
                            text: "every HPX collective, flat and as a tree, built into the program" }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: "#5a5a5a" }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ExampleList {
                        width: parent.width - 16
                        onChosen: (file) => hpxWindow.openFile(file)
                    }
                }
            }
        }
    }

    Dialog {
        id: examplesDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        title: "Examples"
        width: Math.min(hpxWindow.width - 60, 940)
        height: Math.min(hpxWindow.height - 60, 700)
        standardButtons: Dialog.Close
        ScrollView {
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth
            ExampleList {
                width: parent.width - 16
                onChosen: (file) => { examplesDialog.close(); hpxWindow.openFile(file); }
            }
        }
    }
}
