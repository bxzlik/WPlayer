import QtQuick
import QtQuick.Controls

// Кнопка в стиле .ui-btn из Bloom: тонированная (по умолчанию) или primary (акцент)
AbstractButton {
    id: root

    property string iconName: ""
    property bool primary: false
    property bool compact: false
    property bool large: false

    focusPolicy: Qt.NoFocus
    hoverEnabled: true
    topPadding: compact ? 6 : large ? 12 : 9
    bottomPadding: topPadding
    leftPadding: compact ? 11 : large ? 20 : 18
    rightPadding: leftPadding
    font.family: Theme.font
    font.pixelSize: compact ? 12 : large ? 14 : 13
    font.weight: Theme.bold
    opacity: enabled ? 1 : 0.4

    readonly property color fg: primary ? Theme.accentText
                              : (hovered || down) ? Theme.text : Theme.text2

    background: Rectangle {
        radius: Theme.radiusSm
        color: root.primary
               ? (root.hovered || root.down ? Theme.accentHover : Theme.accent)
               : Theme.film(root.down ? 0.12 : root.hovered ? 0.09 : 0.05)
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 7

            Icon {
                visible: root.iconName !== ""
                anchors.verticalCenter: parent.verticalCenter
                iconName: root.iconName
                size: root.font.pixelSize + 4
                color: root.fg
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                font: root.font
                color: root.fg
            }
        }
    }
}
