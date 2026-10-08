import QtQuick
import QtQuick.Controls

// Переключатель как .ui-switch в Bloom: 44×24, ручка 18, отступ 3
AbstractButton {
    id: root

    checkable: true
    focusPolicy: Qt.NoFocus
    hoverEnabled: true
    implicitWidth: 44
    implicitHeight: 24
    opacity: enabled ? 1 : 0.45

    background: Rectangle {
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.film(0.12)
        Behavior on color { ColorAnimation { duration: 200 } }

        Rectangle {
            width: 18
            height: 18
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? Theme.accentText : "#ffffff"
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    contentItem: Item {}
}
