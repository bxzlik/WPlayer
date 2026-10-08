import QtQuick

// Короткое уведомление поверх видео
Rectangle {
    id: root

    property bool isError: false

    function show(message, error) {
        label.text = message
        isError = !!error
        timer.interval = isError ? 6000 : 1600
        opacity = 1
        timer.restart()
    }

    width: content.width + 32
    height: content.height + 22
    radius: Theme.radius
    color: Theme.surface
    border.color: isError ? Qt.rgba(0.9, 0.28, 0.3, 0.45) : Theme.line
    opacity: 0
    visible: opacity > 0
    scale: 0.96 + 0.04 * opacity
    Behavior on opacity { NumberAnimation { duration: 180 } }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 10

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.isError
            iconName: "info"
            size: 18
            color: Theme.danger
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 540)
            wrapMode: Text.Wrap
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    Timer {
        id: timer
        onTriggered: root.opacity = 0
    }
}
