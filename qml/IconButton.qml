import QtQuick
import QtQuick.Controls

// «Прозрачная» иконочная кнопка (как .ui-btn.ghost в Bloom): без подложки,
// на наведении иконка просто светлеет. active — режим включён (акцент).
AbstractButton {
    id: root

    property string iconName: ""
    property string label: ""          // текст вместо иконки
    property int iconSize: 20
    property bool active: false
    property string tip: ""
    property color restColor: Theme.iconFg

    readonly property color fg: !enabled ? Theme.muted
                              : active ? Theme.accent
                              : (hovered || down) ? Theme.text
                              : restColor

    readonly property real labelWidth: labelText.implicitWidth

    implicitWidth: Math.max(36, (label !== "" ? labelWidth + 16 : iconSize + 16))
    implicitHeight: 36
    focusPolicy: Qt.NoFocus
    hoverEnabled: true

    ToolTip {
        visible: root.hovered && root.tip !== ""
        delay: 700
        text: root.tip
        padding: 8
        topPadding: 6
        bottomPadding: 6
        contentItem: Text {
            text: root.tip
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 12
        }
        background: Rectangle {
            color: Theme.surface
            radius: 8
            border.color: Theme.line
        }
    }

    background: Item {}

    contentItem: Item {
        Icon {
            anchors.centerIn: parent
            visible: root.label === ""
            iconName: root.iconName
            size: root.iconSize
            color: root.fg
            scale: root.down ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
        }
        Text {
            id: labelText
            anchors.centerIn: parent
            visible: root.label !== ""
            text: root.label
            color: root.fg
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Theme.bold
        }
    }
}
