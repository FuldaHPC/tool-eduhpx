import QtQuick
import QtQuick3D

// The tree of a collective in 3D, in the style of the 3D view of the EduMPI GUI: every node of the cluster is a pale glass cube,
// the localities that run on it are small cubes inside it (a 3D grid, the number of the locality on the faces), and the
// messages are lines between the cubes. The colour of a locality is the time at which the data reached it (green early, red
// late; for a collective whose data moves up the tree: when the locality had the data of all its children).
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

    property real yaw: 12
    property real pitch: 9
    property real dist: 900

    // ---------------------------------------------------------------- layout (as in the EduMPI GUI: two columns of nodes, four rows)
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
                    x: cols > 1 ? (col - 0.5) * dx : 0, y: -(row - (nRows - 1) / 2) * dy, z: -(block - (nBlocks - 1) / 2) * dz};
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

    function resetView() {
        yaw = 12; pitch = 9;
        userZoomed = false;
        fitView();
    }
    // the distance at which the whole scene fills the window (the camera sees 60 degrees vertically)
    property bool userZoomed: false
    function fitView() {
        if (userZoomed || view.width < 10 || view.height < 10)
            return;
        const half = Math.tan(30 * Math.PI / 180), aspect = view.width / Math.max(view.height, 10);
        const w = layout.width + layout.depth * 0.35 + 60, h = layout.height + 90;      // + room for the names below the cubes
        dist = Math.max(250, Math.max(h / 2 / half, w / 2 / (half * aspect)) * 1.12 + layout.depth / 2);
    }
    Component.onCompleted: resetView()

    // when the data reached every locality, from the start of the group (colour scale: green = first, red = last)
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
    function heat(t) {                    // 0 = green ... 1 = red, through a dark yellow like the EduMPI GUI
        const x = Math.max(0, Math.min(1, t));
        return Qt.hsla((1 - x) * 0.33, 0.8, 0.45, 1);
    }
    function onPath(loc) {
        return crit && (pathChain.indexOf("L#" + loc + " ") >= 0 || pathChain.endsWith("L#" + loc));
    }

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
        readonly property real head: arrow ? Math.min(radius * 5 + 5, len * 0.4) : 0
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
        Model {
            visible: bar.arrow
            source: "#Cone"
            property int edgeIndex: bar.edgeIndex
            pickable: true
            position: bar.b.minus(bar.dir.times(bar.head / 2))
            rotation: bar.rot
            scale: Qt.vector3d(bar.radius * 2.8 / 50, bar.head / 100, bar.radius * 2.8 / 50)
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

        // the localities: a cube each, coloured by the arrival of the data, the number on the faces
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
                    scale: Qt.vector3d(k, k, k)
                    materials: DefaultMaterial {
                        diffuseColor: root.heat((root.arrival[modelData.loc] || 0) / root.arrivalMax)
                        opacity: 0.72
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
                                    font.pixelSize: modelData.loc > 99 ? 50 : 72
                                    font.bold: true
                                }
                            }
                        }
                        cullMode: Material.NoCulling
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

        // the edges: data (thicker) and request (thin) next to each other
        Repeater3D {
            model: root.edges
            delegate: Node {
                id: edgeNode
                required property var modelData
                required property int index
                readonly property vector3d pa: root.layout.pos[modelData.p] || Qt.vector3d(0, 0, 0)
                readonly property vector3d pc: root.layout.pos[modelData.c] || Qt.vector3d(0, 0, 0)
                readonly property vector3d d: pc.minus(pa)
                // sideways offset of the request line, perpendicular to the edge and to the vertical
                readonly property vector3d side: {
                    const s = Qt.vector3d(-d.z, 0, d.x);
                    return s.length() > 0.001 ? s.normalized().times(root.layout.size * 0.14) : Qt.vector3d(root.layout.size * 0.14, 0, 0);
                }
                readonly property bool hot: root.hover === index
                readonly property bool onPath: root.crit && modelData.data.crit
                readonly property real alpha: (hot || onPath || !root.crit) ? 1 : 0.22
                readonly property real r0: root.layout.size * 0.5
                readonly property vector3d u: d.times(1 / Math.max(d.length(), 1))
                // the lines start and end at the surface of the cubes
                readonly property vector3d s0: pa.plus(u.times(r0))
                readonly property vector3d s1: pc.minus(u.times(r0))
                readonly property real wData: root.layout.size * (0.05 + Math.min(Math.sqrt(modelData.data.size) / 150, 2) * 0.012)
                Bar {
                    a: modelData.up ? edgeNode.s1.plus(edgeNode.side.times(-0.5)) : edgeNode.s0.plus(edgeNode.side.times(-0.5))
                    b: modelData.up ? edgeNode.s0.plus(edgeNode.side.times(-0.5)) : edgeNode.s1.plus(edgeNode.side.times(-0.5))
                    radius: edgeNode.wData * (edgeNode.hot || edgeNode.onPath ? 1.5 : 1)
                    color: edgeNode.hot ? "#ff4081" : (edgeNode.onPath ? "#e0a800" : "#1f1f1f")
                    alpha: edgeNode.alpha
                    dashed: modelData.data.missing === true
                    edgeIndex: edgeNode.index
                }
                Bar {
                    visible: modelData.req !== undefined && modelData.req !== null
                    a: modelData.up ? edgeNode.s0.plus(edgeNode.side.times(0.5)) : edgeNode.s1.plus(edgeNode.side.times(0.5))
                    b: modelData.up ? edgeNode.s1.plus(edgeNode.side.times(0.5)) : edgeNode.s0.plus(edgeNode.side.times(0.5))
                    radius: edgeNode.wData * 0.45 * (edgeNode.hot || edgeNode.onPath ? 1.5 : 1)
                    color: edgeNode.hot ? "#ff4081" : (edgeNode.onPath ? "#e0a800" : "#fb8c00")
                    alpha: edgeNode.alpha
                    dashed: modelData.req ? modelData.req.missing === true : false
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
            text: (root.hostNames[modelData.id] || ("node " + (modelData.id + 1))) + "  (" + modelData.locs.length + ")"
            color: "#444444"
            font.pixelSize: 13
            font.bold: true
        }
    }

    // bar at the top as in the EduMPI GUI: heading and colour scale
    Rectangle {
        id: topBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 46
        color: "#9e9e9e"
        Text {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: 16
            font.bold: true
            text: "3D Cluster View: " + (root.treeUp ? "when the node had the data of all its children" : "arrival of the data")
        }
        Row {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 8
            Text { color: "white"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter; text: "start" }
            Rectangle {
                width: 220; height: 14; radius: 2
                anchors.verticalCenter: parent.verticalCenter
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.heat(0) }
                    GradientStop { position: 0.35; color: root.heat(0.35) }
                    GradientStop { position: 0.7; color: root.heat(0.7) }
                    GradientStop { position: 1.0; color: root.heat(1) }
                }
            }
            Text {
                color: "white"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter
                text: root.win ? "+" + root.win.fmtUs(root.arrivalMax) : ""
            }
        }
    }

    // the edge under the mouse
    Rectangle {
        visible: root.hover >= 0 && root.hover < root.edges.length
        x: 14; y: topBar.height + 10
        width: info.width + 16; height: info.height + 10
        radius: 4
        color: "#dd303030"
        Text {
            id: info
            x: 8; y: 5
            color: "white"
            font.pixelSize: 12
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
        text: "glass cube = node, small cube = locality (its number), colour = arrival of the data   black: data   orange: request   gold: critical path   "
              + "drag: turn   wheel or pinch: zoom   double click: reset"
    }

    // ---------------------------------------------------------------- mouse
    HoverHandler {
        onPointChanged: {
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
            root.userZoomed = true;
            root.dist = Math.max(120, Math.min(12000, root.dist * Math.pow(0.9985, e.angleDelta.y)));
        }
    }
    PinchHandler {
        target: null
        property real start: 1
        onActiveChanged: if (active) { start = root.dist; root.userZoomed = true; }
        onActiveScaleChanged: if (active) root.dist = Math.max(120, Math.min(12000, start / Math.max(activeScale, 0.05)))
    }
    TapHandler { onDoubleTapped: root.resetView() }
}
