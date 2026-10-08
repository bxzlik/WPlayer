import QtQuick
import QtQuick.Controls

// Тонкий слайдер: дорожка утолщается и появляется ручка при наведении
Slider {
    id: root

    property color fillColor: Theme.accent
    property real trackAlpha: 0.16
    readonly property bool hovering: hoverHandler.hovered
    readonly property bool active: hovering || pressed
    readonly property real hoverX: hoverHandler.point.position.x

    implicitWidth: 120
    implicitHeight: 20
    padding: 0
    focusPolicy: Qt.NoFocus

    HoverHandler { id: hoverHandler }

    background: Item {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.availableWidth
        height: root.active ? 6 : 4
        Behavior on height { NumberAnimation { duration: 120 } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.film(root.trackAlpha)
        }
        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: height / 2
            color: root.fillColor
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * root.availableWidth - width / 2
        y: root.topPadding + (root.availableHeight - height) / 2
        width: 14
        height: 14
        radius: 7
        color: root.fillColor
        border.width: 2
        border.color: Theme.bg
        scale: root.active ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 120 } }
    }
}
