import QtQuick
import QtQuick.Controls

// Запись истории: значок источника, название, «12:34 / 23:51 · 2 ч назад»,
// полоска просмотренного. При наведении справа — «убрать из истории».
AbstractButton {
    id: root

    // { video, audio, title, position, duration, watchedAt }
    required property var entry
    // Досмотрено до конца (History.finished)
    property bool watched: false

    signal removeClicked()

    readonly property bool remote: entry.video.indexOf("://") >= 0
    readonly property bool hasProgress: !watched && entry.duration > 0 && entry.position > 0

    implicitHeight: 56
    hoverEnabled: true
    focusPolicy: Qt.NoFocus

    background: Rectangle {
        radius: Theme.radiusSm * 1.2
        color: Theme.film(root.down ? 0.08 : root.hovered ? 0.05 : 0)
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    contentItem: Item {
        Rectangle {
            id: badge
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 10
            color: Theme.film(0.05)
            border.color: Theme.line

            Icon {
                anchors.centerIn: parent
                iconName: root.remote ? "link" : "video"
                size: 17
                color: root.hovered ? Theme.text : Theme.text2
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 12
            anchors.right: removeButton.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                width: parent.width
                text: root.entry.title || Theme.sourceName(root.entry.video)
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Theme.bold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: {
                    const parts = []
                    if (root.watched) parts.push("Просмотрено")
                    else if (root.hasProgress)
                        parts.push(Theme.formatTime(root.entry.position) + " / " + Theme.formatTime(root.entry.duration))
                    else if (root.entry.duration > 0) parts.push(Theme.formatTime(root.entry.duration))
                    if (root.entry.audio) parts.push("+ аудио")
                    if (root.entry.watchedAt) parts.push(Theme.timeAgo(root.entry.watchedAt))
                    return parts.join("  ·  ")
                }
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 11
                font.features: { "tnum": 1 }
                elide: Text.ElideRight
            }
            Item {
                width: parent.width
                height: 3
                visible: root.hasProgress

                Rectangle {
                    anchors.fill: parent
                    radius: 1.5
                    color: Theme.film(0.12)
                }
                Rectangle {
                    width: parent.width * Math.min(1, root.entry.position / root.entry.duration)
                    height: parent.height
                    radius: 1.5
                    color: Theme.accent
                }
            }
        }

        IconButton {
            id: removeButton
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.hovered ? 1 : 0
            enabled: root.hovered
            implicitWidth: 32
            implicitHeight: 32
            iconName: "close"
            iconSize: 14
            restColor: Theme.text2
            onClicked: root.removeClicked()
        }
    }
}
