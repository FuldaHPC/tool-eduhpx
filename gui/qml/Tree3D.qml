import QtQuick
import QtQuick3D

// The tree of a collective in 3D, with the nodes (hosts) of the cluster: every node is a slab, the localities that run on it stand
// above it on a stilt, the height of a locality is its depth in the tree (root on top). An edge that leaves the slab of its
// locality goes to another node: the network is between the slabs. Data = white (up: the arrow points to the parent), request
// = orange, gold = critical path, as in the flat tree.
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

    property real yaw: 28
    property real pitch: 26
    property real dist: 900
    readonly property real stepY: 70
    readonly property real slabH: 14

    // ---------------------------------------------------------------- layout
    // hosts that carry a locality of the tree; every host: its localities (in order), the size of the slab and the position
    property var layout: computeLayout()
    function computeLayout() {
        const byHost = {};
        for (const n of nodes) {
            const h = hostOf[n.loc] !== undefined ? hostOf[n.loc] : 0;
            (byHost[h] = byHost[h] || []).push(n.loc);
        }
        const ids = Object.keys(byHost).map(Number).sort((a, b) => a - b);
        const hosts = ids.map(h => {
            const locs = byHost[h].sort((a, b) => a - b);
            const r = Math.max(64, locs.length * 46 / (2 * Math.PI));
            return {id: h, locs: locs, r: r, half: r + 50, x: 0, z: 0};
        });
        let sum = 0;
        for (const h of hosts)
            sum += 2 * h.half + 60;
        const ring = hosts.length > 1 ? Math.max(sum / (2 * Math.PI), hosts[0].half * 1.4) : 0;
        hosts.forEach((h, i) => {
            const a = 2 * Math.PI * i / Math.max(hosts.length, 1) - Math.PI / 2;
            h.x = ring * Math.cos(a);
            h.z = ring * Math.sin(a);
        });
        const pos = {};
        let extent = 150;
        for (const h of hosts) {
            h.locs.forEach((loc, k) => {
                const a = 2 * Math.PI * k / h.locs.length;
                const rr = h.locs.length > 1 ? h.r : 0;
                const depth = (nodes.find(n => n.loc === loc) || {depth: 0}).depth;
                pos[loc] = Qt.vector3d(h.x + rr * Math.cos(a), slabH + 38 + (treeDepth - depth) * stepY, h.z + rr * Math.sin(a));
            });
            extent = Math.max(extent, Math.hypot(h.x, h.z) + h.half);
        }
        return {hosts: hosts, pos: pos, extent: extent, height: slabH + 38 + treeDepth * stepY};
    }
    onNodesChanged: { layout = computeLayout(); resetView(); }
    onTreeDepthChanged: layout = computeLayout()
    onHostOfChanged: layout = computeLayout()

    function resetView() {
        yaw = 28; pitch = 26;
        dist = Math.max(420, layout.extent * 1.55 + layout.height * 0.7);
    }
    Component.onCompleted: resetView()

    function hostColor(i, light) {
        return Qt.hsla((i * 0.17 + 0.08) % 1, 0.55, light, 1);
    }
    function hostIndexOf(h) {            // position of a host among the drawn ones (stable colour)
        return layout.hosts.findIndex(x => x.id === h);
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

    // a line with an optional arrow head: from a to b, shaft and cone along the way
    component Bar: Node {
        id: bar
        property vector3d a
        property vector3d b
        property real radius: 2
        property color color: "white"
        property real alpha: 1
        property bool arrow: true
        property bool dashed: false
        property int edgeIndex: -1
        readonly property real len: Math.max(a.minus(b).length(), 1)
        readonly property vector3d dir: b.minus(a).times(1 / len)
        readonly property real head: arrow ? Math.min(radius * 5 + 6, len * 0.4) : 0
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
                opacity: bar.alpha * (bar.dashed ? 0.55 : 1)
                blendMode: DefaultMaterial.SourceOver
            }
        }
        Model {
            visible: bar.arrow
            source: "#Cone"
            property int edgeIndex: bar.edgeIndex
            pickable: true
            position: bar.b.minus(bar.dir.times(bar.head / 2))
            rotation: bar.rot
            scale: Qt.vector3d(bar.radius * 2.6 / 50, bar.head / 100, bar.radius * 2.6 / 50)
            materials: DefaultMaterial {
                diffuseColor: bar.color
                lighting: DefaultMaterial.NoLighting
                opacity: bar.alpha
            }
        }
    }

    View3D {
        id: view
        anchors.fill: parent
        camera: cam
        environment: SceneEnvironment {
            clearColor: "#2b2b2b"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }

        Node {
            id: rig
            position: Qt.vector3d(0, Math.max(root.layout.height * 0.4, 40), 0)
            eulerRotation: Qt.vector3d(-root.pitch, root.yaw, 0)
            PerspectiveCamera {
                id: cam
                position: Qt.vector3d(0, 0, root.dist)
                clipNear: 5
                clipFar: 20000
            }
        }
        DirectionalLight { eulerRotation: Qt.vector3d(-40, -30, 0); brightness: 1.1 }
        DirectionalLight { eulerRotation: Qt.vector3d(30, 150, 0); brightness: 0.5 }

        // the nodes: a slab each, with a floor grid-like border
        Repeater3D {
            model: root.layout.hosts
            delegate: Node {
                required property var modelData
                required property int index
                position: Qt.vector3d(modelData.x, 0, modelData.z)
                Model {
                    source: "#Cube"
                    position: Qt.vector3d(0, root.slabH / 2, 0)
                    scale: Qt.vector3d(modelData.half * 2 / 100, root.slabH / 100, modelData.half * 2 / 100)
                    materials: DefaultMaterial { diffuseColor: root.hostColor(index, 0.28) }
                }
            }
        }

        // a stilt from the slab to every locality, in the colour of the node
        Repeater3D {
            model: root.nodes
            delegate: Model {
                required property var modelData
                readonly property vector3d p: root.layout.pos[modelData.loc] || Qt.vector3d(0, 0, 0)
                readonly property real h: Math.max(p.y - root.slabH, 1)
                source: "#Cylinder"
                position: Qt.vector3d(p.x, root.slabH + h / 2, p.z)
                scale: Qt.vector3d(0.03, h / 100, 0.03)
                materials: DefaultMaterial {
                    diffuseColor: root.hostColor(root.hostIndexOf(root.hostOf[modelData.loc] !== undefined ? root.hostOf[modelData.loc] : 0), 0.62)
                    lighting: DefaultMaterial.NoLighting
                    opacity: 0.8
                }
            }
        }

        // the localities
        Repeater3D {
            model: root.nodes
            delegate: Node {
                required property var modelData
                readonly property vector3d p: root.layout.pos[modelData.loc] || Qt.vector3d(0, 0, 0)
                readonly property bool path: root.onPath(modelData.loc)
                readonly property int hi: root.hostIndexOf(root.hostOf[modelData.loc] !== undefined ? root.hostOf[modelData.loc] : 0)
                position: p
                Model {
                    source: "#Sphere"
                    scale: Qt.vector3d(0.26, 0.26, 0.26).times(modelData.depth === 0 ? 1.3 : 1)
                    materials: DefaultMaterial { diffuseColor: root.hostColor(hi, 0.58) }
                }
                Model {                                   // a gold shell around the localities of the critical path
                    visible: path
                    source: "#Sphere"
                    scale: Qt.vector3d(0.36, 0.36, 0.36).times(modelData.depth === 0 ? 1.3 : 1)
                    materials: DefaultMaterial {
                        diffuseColor: "#ffd600"
                        lighting: DefaultMaterial.NoLighting
                        opacity: 0.45
                    }
                }
            }
        }

        // the edges: data (thick) and request (thin) next to each other
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
                    return s.length() > 0.001 ? s.normalized().times(6) : Qt.vector3d(6, 0, 0);
                }
                readonly property bool hot: root.hover === index
                readonly property bool onPath: root.crit && modelData.data.crit
                readonly property real alpha: (hot || onPath || !root.crit) ? 1 : 0.3
                readonly property real r0: 13        // the sphere
                readonly property vector3d u: d.times(1 / Math.max(d.length(), 1))
                // the lines start and end at the surface of the spheres
                readonly property vector3d s0: pa.plus(u.times(r0))
                readonly property vector3d s1: pc.minus(u.times(r0))
                Bar {
                    a: modelData.up ? edgeNode.s1.plus(edgeNode.side.times(-0.5)) : edgeNode.s0.plus(edgeNode.side.times(-0.5))
                    b: modelData.up ? edgeNode.s0.plus(edgeNode.side.times(-0.5)) : edgeNode.s1.plus(edgeNode.side.times(-0.5))
                    radius: (2 + Math.min(Math.sqrt(modelData.data.size) / 150, 2)) * (edgeNode.hot || edgeNode.onPath ? 1.4 : 1)
                    color: edgeNode.hot ? "#ff4081" : (edgeNode.onPath ? "#ffd600" : "#ffffff")
                    alpha: edgeNode.alpha
                    dashed: modelData.data.missing === true
                    edgeIndex: edgeNode.index
                }
                Bar {
                    visible: modelData.req !== undefined && modelData.req !== null
                    a: modelData.up ? edgeNode.s0.plus(edgeNode.side.times(0.5)) : edgeNode.s1.plus(edgeNode.side.times(0.5))
                    b: modelData.up ? edgeNode.s1.plus(edgeNode.side.times(0.5)) : edgeNode.s0.plus(edgeNode.side.times(0.5))
                    radius: 1.2 * (edgeNode.hot || edgeNode.onPath ? 1.5 : 1)
                    color: edgeNode.hot ? "#ff4081" : (edgeNode.onPath ? "#ffd600" : "#ffb74d")
                    alpha: edgeNode.alpha
                    dashed: modelData.req ? modelData.req.missing === true : false
                    edgeIndex: edgeNode.index
                }
            }
        }
    }

    // labels in 2D on top of the scene: L#n above every locality, the name below every slab
    Repeater {
        model: root.nodes
        delegate: Text {
            required property var modelData
            readonly property vector3d p: {
                root.yaw; root.pitch; root.dist; view.width; view.height;
                const q = root.layout.pos[modelData.loc] || Qt.vector3d(0, 0, 0);
                return view.mapFrom3DScene(q.plus(Qt.vector3d(0, 24, 0)));
            }
            // many localities: only the root, the critical path and the ends of the edge under the mouse carry a label
            readonly property bool wanted: root.nodes.length <= 24 || modelData.depth === 0 || root.onPath(modelData.loc)
                || (root.hover >= 0 && root.hover < root.edges.length && (root.edges[root.hover].p === modelData.loc || root.edges[root.hover].c === modelData.loc))
            visible: p.z > 0 && wanted
            x: p.x - width / 2
            y: p.y - height
            text: "L#" + modelData.loc
            color: root.onPath(modelData.loc) ? "#ffd600" : "#ffffff"
            font.pixelSize: 12
            font.bold: true
        }
    }
    Repeater {
        model: root.layout.hosts
        delegate: Text {
            required property var modelData
            required property int index
            readonly property vector3d p: {
                root.yaw; root.pitch; root.dist; view.width; view.height;
                return view.mapFrom3DScene(Qt.vector3d(modelData.x, 0, modelData.z + modelData.half + 6));
            }
            visible: p.z > 0
            x: p.x - width / 2
            y: p.y
            text: (root.hostNames[modelData.id] || ("node " + (modelData.id + 1))) + "  (" + modelData.locs.length + ")"
            color: root.hostColor(index, 0.72)
            font.pixelSize: 13
            font.bold: true
        }
    }

    // the edge under the mouse
    Rectangle {
        visible: root.hover >= 0 && root.hover < root.edges.length
        x: 14; y: 12
        width: info.width + 16; height: info.height + 10
        radius: 4
        color: "#cc202020"
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
        color: "#999999"
        font.pixelSize: 11
        text: "slab = node, stilt = locality on it, height = depth in the tree   white: data   orange: request   gold: critical path   "
              + "drag: turn   wheel or pinch: zoom   double click: reset"
    }

    // ---------------------------------------------------------------- mouse
    HoverHandler {
        id: hoverer
        onPointChanged: {
            const r = view.pick(point.position.x, point.position.y);
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
            root.yaw -= (translation.x - lastX) * 0.4;
            root.pitch = Math.max(-80, Math.min(85, root.pitch + (translation.y - lastY) * 0.4));
            lastX = translation.x; lastY = translation.y;
        }
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (e) => root.dist = Math.max(120, Math.min(8000, root.dist * Math.pow(0.9985, e.angleDelta.y)))
    }
    PinchHandler {
        id: pinch
        target: null
        property real start: 1
        onActiveChanged: if (active) start = root.dist
        onActiveScaleChanged: if (active) root.dist = Math.max(120, Math.min(8000, start / Math.max(activeScale, 0.05)))
    }
    TapHandler { onDoubleTapped: root.resetView() }
}
