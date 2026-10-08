import QtQuick
import QtQuick.Templates as T

// Поле ввода как .ui-input в Bloom; capsule — вариант для шторок (44px, полная дуга)
T.TextField {
    id: root

    property bool capsule: false

    implicitWidth: 200
    implicitHeight: capsule ? 44 : 38
    leftPadding: capsule ? 16 : 12
    rightPadding: leftPadding
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter

    color: Theme.text
    selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
    selectedTextColor: Theme.text
    placeholderTextColor: Theme.muted
    font.family: Theme.font
    font.pixelSize: capsule ? 14 : 13
    selectByMouse: true

    background: Rectangle {
        radius: root.capsule ? height / 2 : Theme.radiusSm
        color: root.capsule ? Theme.bg : Theme.film(0.05)
        border.width: 1
        border.color: root.activeFocus ? Theme.line2 : Theme.line
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    Text {
        x: root.leftPadding
        width: root.width - root.leftPadding - root.rightPadding
        height: root.height
        verticalAlignment: Text.AlignVCenter
        visible: root.text === "" && root.preeditText === ""
        text: root.placeholderText
        color: root.placeholderTextColor
        font: root.font
        elide: Text.ElideRight
    }
}
