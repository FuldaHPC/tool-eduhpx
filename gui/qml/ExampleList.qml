import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The example run files that are built into the program, one row per collective with one button per run.
// The list comes from examples/index.json (written by tools/make_examples_index.py).
ColumnLayout {
    id: root
    signal chosen(string file)
    readonly property string dir: "qrc:/qt/qml/EduHPX/examples/"
    property var collectives: []
    spacing: 12

    Component.onCompleted: {
        const req = new XMLHttpRequest();
        req.open("GET", root.dir + "index.json");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            try {
                root.collectives = JSON.parse(req.responseText).collectives;
            } catch (e) {
                root.collectives = [];
            }
        };
        req.send();
    }

    Repeater {
        model: root.collectives
        delegate: ColumnLayout {
            id: row
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            Label { color: "white"; font.bold: true; font.pixelSize: 15; text: row.modelData.title }
            Label {
                Layout.fillWidth: true
                visible: row.modelData.note !== ""
                color: "#bbbbbb"
                wrapMode: Text.WordWrap
                text: row.modelData.note
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: row.modelData.examples
                    delegate: Button {
                        required property var modelData
                        text: modelData.localities > 0
                              ? (modelData.kind === "flat" ? "flat" : "tree") + " · " + modelData.localities + " loc · " + modelData.nodes + " nodes"
                              : "open"
                        onClicked: root.chosen(root.dir + modelData.file)
                    }
                }
            }
        }
    }
}
