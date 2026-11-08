import QtQuick
import QtQuick.Controls
import QtQuick3D

// The tree of a collective in 3D, like the 3D cluster view of the EduMPI GUI: every node of the cluster is a pale glass cube
// (the first node bottom left), the localities that run on it are small numbered cubes inside it, and the messages of the
// tree are lines between the cubes: a green line for every send, a red line for every receive (each can be switched off).
// The colour of a locality, as in the EduMPI GUI:
//   send/recv ratio   green = it sent more, red = it received more, olive = about the same, white = no communication
//   max send          white to green: how much it sent, relative to the locality that sent the most
//   max recv          white to red: how much it received, relative to the locality that received the most
//   arrival of data   (only here) green = the data reached it first, red = last
//
// Input (set by Main.qml): nodes {loc, depth}, edges {p, c, data, req, up}, hostOf (host number of every locality), hostNames,
// and the window for the formatting and the times. Mouse: drag = turn, wheel or pinch = zoom, double click = reset.
Item {
    id: root
    property var win: null
    property var nodes: []
    property var edges: []
    property var hostOf: []
    property var hostNames: []
    property bool crit: false
    property string pathChain: ""
    property bool treeUp: false
    property int treeDepth: 0
    property int hover: -1                // edge under the mouse
    property real mouseX: 0               // where the mouse is, for the box that shows the edge
    property real mouseY: 0

    property string mode: "ratio"         // ratio | send | recv | arrival
    property bool showSend: true
    property bool showRecv: true
    // the choices are kept in the window, so that they stay when another view is shown in between
    onModeChanged: if (win) win.tree3dMode = mode
    onShowSendChanged: if (win) win.tree3dSend = showSend
    onShowRecvChanged: if (win) win.tree3dRecv = showRecv

    property real yaw: 12
    property real pitch: 9
    property real dist: 900

    // ---------------------------------------------------------------- layout (as in the EduMPI GUI: two columns of nodes, four rows,
    // the first node bottom left, then to the right and up)
    property var layout: computeLayout()
    function hostOfLoc(loc) { return hostOf[loc] !== undefined ? hostOf[loc] : 0; }
    function computeLayout() {
        const byHost = {};
        for (const n of nodes)
            (byHost[hostOfLoc(n.loc)] = byHost[hostOfLoc(n.loc)] || []).push(n.loc);
        const ids = Object.keys(byHost).map(Number).sort((a, b) => a - b);
        let maxN = 1;
        for (const id of ids)
            maxN = Math.max(maxN, byHost[id].length);
        const rows = Math.max(Math.ceil(Math.cbrt(maxN - 0.001)), 1);       // cubes per edge of the grid inside a node
        const edge = Math.max(120, 38 * rows);                              // edge of the node cube
        const cell = edge / rows, size = cell * 0.55;                       // the localities fill about half of each cell
        const cols = Math.max(Math.min(ids.length, 2), 1), perCol = 4;
        const dx = edge * 4.2, dy = edge * 1.75, dz = edge * 2.6;
        const nRows = Math.max(Math.min(Math.ceil(ids.length / cols), perCol), 1), nBlocks = Math.max(Math.ceil(ids.length / (cols * perCol)), 1);
        const hosts = ids.map((id, i) => {
            const col = i % cols, row = Math.floor(i / cols) % perCol, block = Math.floor(i / (cols * perCol));
            return {id: id, locs: byHost[id].sort((a, b) => a - b),
                    x: cols > 1 ? (col - 0.5) * dx : 0, y: (row - (nRows - 1) / 2) * dy, z: -(block - (nBlocks - 1) / 2) * dz};
        });
        const pos = {};
        for (const h of hosts)
            h.locs.forEach((loc, k) => {
                const ix = k % rows, iy = Math.floor(k / rows) % rows, iz = Math.floor(k / (rows * rows));
                pos[loc] = Qt.vector3d(h.x + (ix - (rows - 1) / 2) * cell, h.y + (iy - (rows - 1) / 2) * cell, h.z + ((rows - 1) / 2 - iz) * cell);
            });
        const width = cols > 1 ? dx + edge : edge, height = (nRows - 1) * dy + edge, depth = (nBlocks - 1) * dz + edge;
        return {hosts: hosts, pos: pos, rows: rows, edge: edge, cell: cell, size: size, width: width, height: height, depth: depth};
    }
    onNodesChanged: { layout = computeLayout(); resetView(); }
    onHostOfChanged: layout = computeLayout()

    // the point the camera looks at (the middle of the scene, or the cube that was clicked) and the locality that was clicked
    property real tx: 0
    property real ty: 0
    property real tz: 0
    property int selected: -1
    function resetView() {                // back to the overview
        selected = -1;
        yaw = 12; pitch = 9;
        userZoomed = false;
        goTo(0, 0, 0, fitDistance());
    }
    function select(loc) {                // fly to a cube
        const q = layout.pos[loc];
        if (!q)
            return;
        selected = loc;
        userZoomed = true;
        goTo(q.x, q.y, q.z, Math.max(90, layout.size * 6));
    }
    function goTo(x, y, z, d) {
        focusAnimation.stop();
        if (!isFinite(d) || view.width < 10) {
            tx = x; ty = y; tz = z;
            if (isFinite(d))
                dist = d;
            return;
        }
        animTx.to = x; animTy.to = y; animTz.to = z; animDist.to = d;
        focusAnimation.start();
    }
    ParallelAnimation {
        id: focusAnimation
        NumberAnimation { id: animTx; target: root; property: "tx"; duration: 350; easing.type: Easing.InOutQuad }
        NumberAnimation { id: animTy; target: root; property: "ty"; duration: 350; easing.type: Easing.InOutQuad }
        NumberAnimation { id: animTz; target: root; property: "tz"; duration: 350; easing.type: Easing.InOutQuad }
        NumberAnimation { id: animDist; target: root; property: "dist"; duration: 350; easing.type: Easing.InOutQuad }
    }
    // the distance at which the whole scene fills the window (the camera sees 60 degrees vertically)
    property bool userZoomed: false
    function fitDistance() {
        if (view.width < 10 || view.height < 10)
            return NaN;
        const half = Math.tan(30 * Math.PI / 180), aspect = view.width / Math.max(view.height, 10);
        const w = layout.width + layout.depth * 0.35 + 60, h = layout.height + 90;      // + room for the names below the cubes
        return Math.max(250, Math.max(h / 2 / half, w / 2 / (half * aspect)) * 1.12 + layout.depth / 2);
    }
    function fitView() {
        if (userZoomed)
            return;
        const d = fitDistance();
        if (isFinite(d))
            dist = d;
    }
    Component.onCompleted: resetView()

    // ---------------------------------------------------------------- the numbers behind the colours
    // bytes every locality sent and received in this group (data and request messages of the tree)
    readonly property var volumes: {
        const s = {}, r = {};
        for (const n of nodes) { s[n.loc] = 0; r[n.loc] = 0; }
        for (const e of edges)
            for (const m of [e.data, e.req])
                if (m) {
                    s[m.src] = (s[m.src] || 0) + m.size;
                    r[m.dst] = (r[m.dst] || 0) + m.size;
                }
        let ms = 0, mr = 0;
        for (const k in s) { ms = Math.max(ms, s[k]); mr = Math.max(mr, r[k]); }
        return {send: s, recv: r, maxSend: ms, maxRecv: mr};
    }
    // when the data reached every locality, from the start of the group
    readonly property var arrival: {
        const a = {};
        for (const n of nodes)
            a[n.loc] = 0;
        if (win) {
            for (const e of edges) {
                const t = e.data.t1 - win.treeStart;
                if (treeUp)
                    a[e.p] = Math.max(a[e.p] || 0, t);       // the parent has the data of this child
                else
                    a[e.c] = t;
            }
        }
        return a;
    }
    readonly property real arrivalMax: {
        let m = 1e-9;
        for (const k in arrival)
            m = Math.max(m, arrival[k]);
        return m;
    }
    function heat(t) {                    // 0 = green ... 1 = red, through a dark yellow
        const x = Math.max(0, Math.min(1, t));
        return Qt.hsla((1 - x) * 0.33, 0.8, 0.45, 1);
    }
    // the colour of a locality in the chosen view; the formulas are those of the EduMPI GUI
    function colorOf(loc) {
        const s = volumes.send[loc] || 0, r = volumes.recv[loc] || 0;
        if (mode === "ratio") {
            const total = s + r;
            return total === 0 ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(r / total, s / total, 0, 1);
        }
        if (mode === "send") {
            const p = volumes.maxSend > 0 ? s / volumes.maxSend : 0;
            return Qt.rgba(1 - p, 1, 1 - p, 1);
        }
        if (mode === "recv") {
            const p = volumes.maxRecv > 0 ? r / volumes.maxRecv : 0;
            return Qt.rgba(1, 1 - p, 1 - p, 1);
        }
        return heat((arrival[loc] || 0) / arrivalMax);
    }
    function onPath(loc) {
        return crit && (pathChain.indexOf("L#" + loc + " ") >= 0 || pathChain.endsWith("L#" + loc));
    }
    readonly property var modeTitles: ({
        ratio: "Send/Recv Ratio per Locality",
        send: "Max Send Ratio (All Localities)",
        recv: "Max Recv Ratio (All Localities)",
        arrival: "Arrival of the Data"
    })
    readonly property var modeTips: ({
        ratio: "Ratio between the data a locality sent and received in this group.\nGreen = it sent more, red = it received more, olive = about the same, white = no communication.",
        send: "How much a locality sent, relative to the locality that sent the most in this group.\nWhite = nothing, green = the most.",
        recv: "How much a locality received, relative to the locality that received the most in this group.\nWhite = nothing, red = the most.",
        arrival: "When the data reached the locality (for reduce and gather: when it had the data of all its children).\nGreen = first, red = last."
    })

    // rotation that turns the Y axis of a cylinder or cone into the direction (dx, dy, dz)
    function rotationTo(dx, dy, dz) {
        const len = Math.hypot(dx, dy, dz) || 1;
        const uy = dy / len, ux = dx / len, uz = dz / len;
        if (uy > 0.99999)
            return Qt.quaternion(1, 0, 0, 0);
        if (uy < -0.99999)
            return Qt.quaternion(0, 1, 0, 0);
        const half = Math.acos(uy) / 2, s = Math.sin(half) / Math.hypot(uz, ux);
        return Qt.quaternion(Math.cos(half), uz * s, 0, -ux * s);
    }

    // a line with an optional arrow head: from a to b
    component Bar: Node {
        id: bar
        property vector3d a
        property vector3d b
        property real radius: 1.4
        property color color: "black"
        property real alpha: 1
        property bool arrow: true
        property bool dashed: false
        property int edgeIndex: -1
        readonly property real len: Math.max(a.minus(b).length(), 1)
        readonly property vector3d dir: b.minus(a).times(1 / len)
        readonly property real head: arrow ? Math.min(radius * 4 + 3, len * 0.35) : 0
        readonly property quaternion rot: root.rotationTo(dir.x, dir.y, dir.z)
        Model {
            source: "#Cylinder"
            pickable: true
            property int edgeIndex: bar.edgeIndex
            position: bar.a.plus(bar.dir.times((bar.len - bar.head) / 2))
            rotation: bar.rot
            scale: Qt.vector3d(bar.radius / 50, Math.max(bar.len - bar.head, 0.1) / 100, bar.radius / 50)
            materials: DefaultMaterial {
                diffuseColor: bar.color
                lighting: DefaultMaterial.NoLighting
                opacity: bar.alpha * (bar.dashed ? 0.5 : 1)
                cullMode: Material.NoCulling
            }
        }
        Model {                                  // an invisible, wider line: thin lines are hard to hit with the mouse
            source: "#Cylinder"
            pickable: true
            property int edgeIndex: bar.edgeIndex
            position: bar.a.plus(bar.dir.times(bar.len / 2))
            rotation: bar.rot
            scale: Qt.vector3d(Math.max(bar.radius * 3, 3.5) / 50, bar.len / 100, Math.max(bar.radius * 3, 3.5) / 50)
            materials: DefaultMaterial {
                diffuseColor: "white"
                lighting: DefaultMaterial.NoLighting
                opacity: 0.0
                depthDrawMode: Material.NeverDepthDraw
            }
        }
        Model {
            visible: bar.arrow
            source: "#Cone"
            property int edgeIndex: bar.edgeIndex
            pickable: true
            position: bar.b.minus(bar.dir.times(bar.head / 2))
            rotation: bar.rot
            scale: Qt.vector3d(bar.radius * 2.3 / 50, bar.head / 100, bar.radius * 2.3 / 50)
            materials: DefaultMaterial {
                diffuseColor: bar.color
                lighting: DefaultMaterial.NoLighting
                opacity: bar.alpha
                cullMode: Material.NoCulling
            }
        }
    }

    View3D {
        id: view
        anchors { left: parent.left; right: parent.right; top: topBar.bottom; bottom: parent.bottom }
        camera: cam
        onWidthChanged: root.fitView()
        onHeightChanged: root.fitView()
        environment: SceneEnvironment {
            clearColor: "white"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }

        Node {
            id: rig
            position: Qt.vector3d(root.tx, root.ty, root.tz)
            eulerRotation: Qt.vector3d(-root.pitch, root.yaw, 0)
            PerspectiveCamera {
                id: cam
                position: Qt.vector3d(0, 0, root.dist)
                clipNear: 5
                clipFar: 20000
            }
        }
        DirectionalLight {
            eulerRotation: Qt.vector3d(250, -30, 0)
            brightness: 0.8
            ambientColor: "#7f7f7f"
        }

        // the nodes: a pale glass cube each
        Repeater3D {
            model: root.layout.hosts
            delegate: Model {
                required property var modelData
                source: "#Cube"
                position: Qt.vector3d(modelData.x, modelData.y, modelData.z)
                scale: Qt.vector3d(root.layout.edge / 100, root.layout.edge / 100, root.layout.edge / 100)
                materials: DefaultMaterial {
                    diffuseColor: "#d9d9d9"
                    opacity: 0.16
                    cullMode: Material.NoCulling
                    depthDrawMode: Material.NeverDepthDraw
                }
            }
        }

        // the localities: a cube each, coloured by the chosen view, the number on the faces
        Repeater3D {
            model: root.nodes
            delegate: Node {
                required property var modelData
                readonly property vector3d p: root.layout.pos[modelData.loc] || Qt.vector3d(0, 0, 0)
                readonly property bool path: root.onPath(modelData.loc)
                readonly property real k: root.layout.size / 100
                position: p
                Model {
                    source: "#Cube"
                    pickable: true
                    property int locId: modelData.loc
                    scale: Qt.vector3d(k, k, k)
                    materials: DefaultMaterial {
                        diffuseColor: root.colorOf(modelData.loc)
                        opacity: (root.showSend || root.showRecv) ? 0.62 : 0.8
                        depthDrawMode: Material.AlwaysDepthDraw
                    }
                }
                Model {                                   // the number of the locality
                    source: "#Cube"
                    scale: Qt.vector3d(k * 1.003, k * 1.003, k * 1.003)
                    materials: DefaultMaterial {
                        lighting: DefaultMaterial.NoLighting
                        diffuseMap: Texture {
                            sourceItem: Rectangle {
                                width: 128; height: 128
                                color: "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: String(modelData.loc)
                                    color: "black"
                                    font.pixelSize: modelData.loc > 99 ? 32 : 44
                                    font.bold: true
                                }
                            }
                        }
                        cullMode: Material.NoCulling
                    }
                }
                Model {                                   // a blue frame around the cube that was clicked
                    visible: root.selected === modelData.loc
                    source: "#Cube"
                    scale: Qt.vector3d(k * 1.22, k * 1.22, k * 1.22)
                    materials: DefaultMaterial {
                        diffuseColor: "#2979ff"
                        lighting: DefaultMaterial.NoLighting
                        opacity: 0.4
                        depthDrawMode: Material.NeverDepthDraw
                    }
                }
                Model {                                   // a gold frame around the localities of the critical path
                    visible: path
                    source: "#Cube"
                    scale: Qt.vector3d(k * 1.18, k * 1.18, k * 1.18)
                    materials: DefaultMaterial {
                        diffuseColor: "#ffc400"
                        lighting: DefaultMaterial.NoLighting
                        opacity: 0.35
                        depthDrawMode: Material.NeverDepthDraw
                    }
                }
            }
        }

        // the messages: for the data and for the request of every edge a green line (the send, from the sender to the receiver)
        // and a red line (the receive, from the receiver to the sender it heard from), next to each other
        Repeater3D {
            model: root.edges
            delegate: Node {
                id: edgeNode
                required property var modelData
                required property int index
                readonly property vector3d pa: root.layout.pos[modelData.p] || Qt.vector3d(0, 0, 0)
                readonly property vector3d pc: root.layout.pos[modelData.c] || Qt.vector3d(0, 0, 0)
                readonly property vector3d d: pc.minus(pa)
                readonly property real unit: root.layout.size * 0.075
                // sideways direction, perpendicular to the edge and to the vertical
                readonly property vector3d side: {
                    const s = Qt.vector3d(-d.z, 0, d.x);
                    return s.length() > 0.001 ? s.normalized() : Qt.vector3d(1, 0, 0);
                }
                readonly property bool hot: root.hover === index
                readonly property bool onPath: root.crit && modelData.data.crit
                readonly property bool touches: root.selected >= 0 && (modelData.p === root.selected || modelData.c === root.selected)
                readonly property real alpha: root.selected >= 0 ? (touches || hot ? 1 : 0.12) : ((hot || onPath || !root.crit) ? 1 : 0.2)
                readonly property real r0: root.layout.size * 0.5
                readonly property vector3d u: d.times(1 / Math.max(d.length(), 1))
                // the lines start and end at the surface of the cubes
                readonly property vector3d s0: pa.plus(u.times(r0))
                readonly property vector3d s1: pc.minus(u.times(r0))
                // the data goes from dFrom to dTo, the request the other way
                readonly property bool up: modelData.up === true
                readonly property vector3d dFrom: up ? s1 : s0
                readonly property vector3d dTo: up ? s0 : s1
                readonly property real wData: root.layout.size * (0.032 + Math.min(Math.sqrt(modelData.data.size) / 150, 2) * 0.007) * (hot || onPath ? 1.15 : 1)
                readonly property real wReq: root.layout.size * 0.02 * (hot || onPath ? 1.15 : 1)
                readonly property bool hasReq: modelData.req !== undefined && modelData.req !== null
                readonly property color sendColor: hot ? "#ff4081" : "#00c853"
                readonly property color recvColor: hot ? "#ff4081" : "#e53935"

                // the critical path: a gold band behind the lines of the edge
                Bar {
                    visible: edgeNode.onPath
                    a: edgeNode.dFrom.plus(edgeNode.side.times(edgeNode.unit * 0.8))
                    b: edgeNode.dTo.plus(edgeNode.side.times(edgeNode.unit * 0.8))
                    radius: edgeNode.unit * 3.2
                    arrow: false
                    color: "#ffc400"
                    alpha: 0.35
                    edgeIndex: edgeNode.index
                }
                // data, sent: green
                Bar {
                    visible: root.showSend
                    a: edgeNode.dFrom.plus(edgeNode.side.times(edgeNode.unit * 2.4))
                    b: edgeNode.dTo.plus(edgeNode.side.times(edgeNode.unit * 2.4))
                    radius: edgeNode.wData
                    color: edgeNode.sendColor
                    alpha: edgeNode.alpha
                    dashed: modelData.data.missing === true
                    edgeIndex: edgeNode.index
                }
                // data, received: red, from the receiver to the sender
                Bar {
                    visible: root.showRecv
                    a: edgeNode.dTo.plus(edgeNode.side.times(edgeNode.unit * 0.8))
                    b: edgeNode.dFrom.plus(edgeNode.side.times(edgeNode.unit * 0.8))
                    radius: edgeNode.wData
                    color: edgeNode.recvColor
                    alpha: edgeNode.alpha
                    dashed: modelData.data.missing === true
                    edgeIndex: edgeNode.index
                }
                // request (or confirmation), sent: green
                Bar {
                    visible: root.showSend && edgeNode.hasReq
                    a: edgeNode.dTo.plus(edgeNode.side.times(-edgeNode.unit * 0.8))
                    b: edgeNode.dFrom.plus(edgeNode.side.times(-edgeNode.unit * 0.8))
                    radius: edgeNode.wReq
                    color: edgeNode.sendColor
                    alpha: edgeNode.alpha
                    dashed: edgeNode.hasReq && modelData.req.missing === true
                    edgeIndex: edgeNode.index
                }
                // request, received: red, from the receiver to the sender
                Bar {
                    visible: root.showRecv && edgeNode.hasReq
                    a: edgeNode.dFrom.plus(edgeNode.side.times(-edgeNode.unit * 2.4))
                    b: edgeNode.dTo.plus(edgeNode.side.times(-edgeNode.unit * 2.4))
                    radius: edgeNode.wReq
                    color: edgeNode.recvColor
                    alpha: edgeNode.alpha
                    dashed: edgeNode.hasReq && modelData.req.missing === true
                    edgeIndex: edgeNode.index
                }
            }
        }
    }

    // the name of every node, below its cube
    Repeater {
        model: root.layout.hosts
        delegate: Text {
            required property var modelData
            readonly property vector3d p: {
                root.yaw; root.pitch; root.dist; view.width; view.height;
                return view.mapFrom3DScene(Qt.vector3d(modelData.x, modelData.y - root.layout.edge * 0.62, modelData.z));
            }
            visible: p.z > 0
            x: p.x - width / 2
            y: p.y + topBar.height
            text: (root.hostNames[modelData.id] || ("node " + (modelData.id + 1)))
            color: "#444444"
            font.pixelSize: 13
            font.bold: true
        }
    }

    // a slim bar at the top: the title, the colour scale, the view to choose and the lines to show
    component Chip: Rectangle {
        id: chip
        property string label
        property bool on: true
        property color tint: "#555555"
        signal toggled()
        height: 26
        width: chipText.width + 26
        radius: height / 2
        color: on ? tint : "white"
        border.color: tint
        border.width: 1.5
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? "white" : chip.tint
            font.pixelSize: 12
            font.bold: true
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.toggled() }
    }
    Rectangle {
        id: topBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 42
        color: "#f2f2f2"
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: "#d6d6d6" }
        Row {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: "#333333"; font.pixelSize: 14; font.bold: true
                text: "3D cluster"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: "#666666"; font.pixelSize: 13
                text: root.modeTitles[root.mode]
            }
            Rectangle {                                    // what the colours mean, on hover
                id: infoDot
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16; radius: 8
                color: "transparent"; border.color: "#888888"
                Text { anchors.centerIn: parent; text: "i"; color: "#777777"; font.pixelSize: 10; font.bold: true }
                MouseArea { id: infoArea; anchors.fill: parent; hoverEnabled: true }
                ToolTip.visible: infoArea.containsMouse
                ToolTip.delay: 200
                ToolTip.text: root.modeTips[root.mode]
            }
        }
        Row {
            id: controls
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 8
            ComboBox {
                id: modeBox
                width: 236; height: 28
                font.pixelSize: 12
                model: [
                    {text: "send/recv ratio (per locality)", key: "ratio"},
                    {text: "max send ratio (across all localities)", key: "send"},
                    {text: "max recv ratio (across all localities)", key: "recv"},
                    {text: "arrival of the data", key: "arrival"}
                ]
                textRole: "text"
                currentIndex: ({ratio: 0, send: 1, recv: 2, arrival: 3})[root.mode]
                onActivated: root.mode = model[currentIndex].key
                background: Rectangle { radius: 6; color: "white"; border.color: modeBox.activeFocus ? "#2979ff" : "#c4c4c4" }
                contentItem: Text {
                    leftPadding: 10; rightPadding: 24
                    text: modeBox.displayText; font: modeBox.font; color: "#333333"
                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                }
                indicator: Text { x: modeBox.width - width - 10; y: (modeBox.height - height) / 2; text: "\u25BE"; color: "#666666"; font.pixelSize: 12 }
            }
            Chip { label: "Send"; tint: "#00a152"; on: root.showSend; onToggled: root.showSend = !root.showSend }
            Chip { label: "Recv"; tint: "#d32f2f"; on: root.showRecv; onToggled: root.showRecv = !root.showRecv }
        }
        // the colour scale
        Row {
            id: scale
            visible: root.width > 1150
            anchors { right: controls.left; rightMargin: 22; verticalCenter: parent.verticalCenter }
            spacing: 7
            Rectangle {                                    // white: no communication
                visible: root.mode === "ratio"
                width: 12; height: 12; radius: 2; color: "white"; border.color: "#999999"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text { visible: root.mode === "ratio"; color: "#666666"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter; text: "none" }
            Text {
                color: "#666666"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "ratio" ? "sent more" : (root.mode === "arrival" ? "start" : "0")
            }
            Rectangle {
                width: 150; height: 12; radius: 3
                anchors.verticalCenter: parent.verticalCenter
                border.color: "#aaaaaa"
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.mode === "arrival" ? root.heat(0) : (root.mode === "ratio" ? "#00ff00" : "white") }
                    GradientStop { position: 0.5; color: root.mode === "arrival" ? root.heat(0.5) : (root.mode === "ratio" ? "#7f7f00" : (root.mode === "send" ? "#7fff7f" : "#ff7f7f")) }
                    GradientStop { position: 1.0; color: root.mode === "arrival" ? root.heat(1) : (root.mode === "ratio" ? "#ff0000" : (root.mode === "send" ? "#00ff00" : "#ff0000")) }
                }
            }
            Text {
                color: "#666666"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (root.mode === "ratio") return "received more";
                    if (root.mode === "send") return root.win ? root.win.fmtSize(root.volumes.maxSend) + " sent" : "";
                    if (root.mode === "recv") return root.win ? root.win.fmtSize(root.volumes.maxRecv) + " received" : "";
                    return root.win ? "+" + root.win.fmtUs(root.arrivalMax) : "";
                }
            }
        }
    }

    // the cube that was clicked: what it did in this group
    function selectedText() {
        if (selected < 0)
            return "";
        const host = hostNames[hostOf[selected]] || "";
        let sentN = 0, recvN = 0, parent = -1;
        const kids = [];
        for (const e of edges) {
            for (const m of [e.data, e.req])
                if (m) {
                    if (m.src === selected) sentN++;
                    if (m.dst === selected) recvN++;
                }
            if (e.c === selected) parent = e.p;
            if (e.p === selected) kids.push(e.c);
        }
        const fmt = win ? win.fmtSize : (v => v + " B"), us = win ? win.fmtUs : (v => v + " us");
        return "L#" + selected + (host ? "  on " + host : "")
               + "\nsent " + fmt(volumes.send[selected] || 0) + " in " + sentN + (sentN === 1 ? " message" : " messages")
               + "\nreceived " + fmt(volumes.recv[selected] || 0) + " in " + recvN + (recvN === 1 ? " message" : " messages")
               + (selected in arrival && arrival[selected] > 0 ? "\n" + (treeUp ? "had the data of all its children at +" : "data arrived at +") + us(arrival[selected]) : "")
               + (parent >= 0 ? "\nparent L#" + parent : "\nroot of the tree")
               + (kids.length > 0 ? "\n" + (kids.length > 6 ? kids.length + " children" : "children " + kids.map(k => "L#" + k).join(", ")) : "");
    }
    Rectangle {
        id: selPanel
        visible: root.selected >= 0
        x: 12; y: topBar.height + 10
        width: Math.max(selText.width, 150) + 24; height: selText.height + backChip.height + 26
        radius: 8
        color: "#262626"
        border.color: "#555555"
        z: 3
        Text {
            id: selText
            x: 12; y: 10
            color: "white"; font.pixelSize: 13; lineHeight: 1.15
            text: root.selectedText()
        }
        Rectangle {
            id: backChip
            x: 12; y: selText.y + selText.height + 8
            width: backText.width + 20; height: 24; radius: 12
            color: "#2979ff"
            Text { id: backText; anchors.centerIn: parent; text: "Back to overview"; color: "white"; font.pixelSize: 12; font.bold: true }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.resetView() }
        }
    }

    // the edge under the mouse
    Rectangle {
        id: infoBox
        visible: root.hover >= 0 && root.hover < root.edges.length
        // next to the pointer, to the right and below it; to the left or above if there is no room
        x: root.mouseX + 18 + width > root.width - 8 ? root.mouseX - 18 - width : root.mouseX + 18
        y: root.mouseY + 18 + height > root.height - 8 ? root.mouseY - 18 - height : root.mouseY + 18
        width: info.width + 16; height: info.height + 10
        radius: 4
        color: "#262626"
        border.color: "#555555"
        z: 2
        Text {
            id: info
            x: 8; y: 5
            color: "white"
            font.pixelSize: 13
            text: {
                if (root.hover < 0 || root.hover >= root.edges.length || !root.win)
                    return "";
                const e = root.edges[root.hover];
                const from = e.up ? e.c : e.p, to = e.up ? e.p : e.c;
                const nh = root.hostNames[root.hostOf[from]] || "", nt = root.hostNames[root.hostOf[to]] || "";
                const same = root.hostOf[from] === root.hostOf[to];
                return "L#" + from + " → L#" + to + "   " + root.win.fmtSize(e.data.size) + (e.data.missing ? " (no MPI message recorded)" : "")
                       + "\narrives +" + root.win.fmtUs(e.data.t1 - root.win.treeStart)
                       + (nh || nt ? "\n" + (same ? "on node " + nh + " (stays in the node)" : nh + " → " + nt + " (over the network)") : "");
            }
        }
    }
    Text {
        x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 12
        color: "#777777"
        font.pixelSize: 11
        text: "green line: send   red line: receive (the arrow points to the sender it heard from)   thick: data, thin: request"
              + (root.crit ? "   gold: critical path" : "")
              + "   click a cube: look at it, scroll out to come back   drag: turn   wheel or pinch: zoom   double click: reset"
    }

    // ---------------------------------------------------------------- mouse
    HoverHandler {
        onPointChanged: {
            root.mouseX = point.position.x;
            root.mouseY = point.position.y;
            const r = view.pick(point.position.x, point.position.y - topBar.height);
            root.hover = r.objectHit && r.objectHit.edgeIndex !== undefined ? r.objectHit.edgeIndex : -1;
        }
        onHoveredChanged: if (!hovered) root.hover = -1
    }
    DragHandler {
        target: null
        property real lastX: 0
        property real lastY: 0
        onActiveChanged: { lastX = 0; lastY = 0; }
        onTranslationChanged: {
            root.userZoomed = true;
            root.yaw -= (translation.x - lastX) * 0.4;
            root.pitch = Math.max(-85, Math.min(85, root.pitch + (translation.y - lastY) * 0.4));
            lastX = translation.x; lastY = translation.y;
        }
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (e) => {
            if (focusAnimation.running && root.selected < 0)       // flying back to the overview: let it arrive
                return;
            focusAnimation.stop();
            const far = root.fitDistance();
            const d = Math.max(root.selected >= 0 ? 50 : 120, Math.min(isFinite(far) ? far * 1.6 : 12000, root.dist * Math.pow(0.9985, e.angleDelta.y)));
            if (root.selected >= 0 && isFinite(far) && d > far * 0.8) {      // scrolled out far enough: back to the overview
                root.resetView();
                return;
            }
            root.userZoomed = true;
            root.dist = d;
        }
    }
    PinchHandler {
        target: null
        property real start: 1
        onActiveChanged: if (active) { start = root.dist; root.userZoomed = true; }
        onActiveScaleChanged: if (active) {
            const far = root.fitDistance();
            root.dist = Math.max(root.selected >= 0 ? 50 : 120, Math.min(isFinite(far) ? far * 1.6 : 12000, start / Math.max(activeScale, 0.05)));
        }
    }
    TapHandler {
        onTapped: (point) => {
            if (point.position.y < topBar.height || (selPanel.visible && point.position.x < selPanel.x + selPanel.width && point.position.y < selPanel.y + selPanel.height))
                return;
            let loc = -1;
            const hits = view.pickAll(point.position.x, point.position.y - topBar.height);
            for (const h of hits)
                if (h.objectHit && h.objectHit.locId !== undefined) { loc = h.objectHit.locId; break; }
            if (loc < 0 || loc === root.selected)
                root.resetView();                     // clicked beside a cube, or the same cube again
            else
                root.select(loc);
        }
        onDoubleTapped: root.resetView()
    }
}
