pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Очередь — шторка справа, как история: что играет, что дальше.
// Клик — включить, крестик — убрать, ручка слева — перетащить.
Popup {
    id: root

    required property MpvObject player

    signal addFiles()
    signal addUrl()

    property real slide: 1
    property bool fullscreen: false
    property real panelTop: (fullscreen ? 0 : 32) + 16
    Behavior on panelTop { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // Перетаскивание: откуда и перед какой записью вставить (-1 — нет)
    property int dragFrom: -1
    property int dropBefore: -1

    readonly property int rowHeight: 48
    readonly property int rowSpacing: 2

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: Math.min(440, parent.width - 32)
    height: parent.height - panelTop - 16
    x: Math.round(parent.width - width - 16 + slide * (width + 40))
    y: panelTop

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.55)
        Behavior on opacity { NumberAnimation { duration: 220 } }
    }

    enter: Transition {
        NumberAnimation {
            property: "slide"; from: 1; to: 0
            duration: Theme.slideDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.slideCurve
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "slide"; from: 0; to: 1
            duration: Theme.slideDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.slideCurve
        }
    }

    background: Rectangle {
        color: Theme.surface
        radius: Theme.radius
    }

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 8
            Layout.topMargin: 12
            Layout.bottomMargin: 8
            spacing: 10

            Text {
                text: "Очередь"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 17
                font.weight: Theme.bold
                font.letterSpacing: -0.3
            }
            Text {
                Layout.fillWidth: true
                text: root.player.playlist.length > 0 ? root.player.playlist.length : ""
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Theme.bold
            }
            PillButton {
                compact: true
                visible: root.player.playlist.length > 1
                text: "Оставить текущее"
                onClicked: root.player.playlistClearOthers()
            }
            IconButton {
                iconName: "close"
                iconSize: 16
                restColor: Theme.text2
                onClicked: root.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 8
            spacing: 8

            PillButton {
                Layout.fillWidth: true
                iconName: "folder"
                text: "Добавить файлы"
                onClicked: root.addFiles()
            }
            PillButton {
                Layout.fillWidth: true
                iconName: "link"
                text: "Ссылку"
                onClicked: root.addUrl()
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds
            interactive: root.dragFrom < 0
            model: root.player.playlist

            delegate: AbstractButton {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: index === root.player.playlistPos

                width: list.width
                height: root.rowHeight
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                opacity: root.dragFrom === index ? 0.4 : 1
                onClicked: if (!current) root.player.playlistPlay(index)

                background: Rectangle {
                    radius: Theme.radiusSm * 1.2
                    color: row.current ? Theme.film(0.06)
                         : Theme.film(row.down ? 0.08 : row.hovered ? 0.05 : 0)
                }

                contentItem: Item {
                    // Ручка перетаскивания
                    Item {
                        id: handle
                        width: 32
                        height: parent.height

                        Icon {
                            anchors.centerIn: parent
                            iconName: "drag"
                            size: 14
                            color: handleArea.containsMouse || handleArea.pressed ? Theme.text : Theme.muted
                            opacity: row.hovered || handleArea.pressed ? 1 : 0.5
                        }
                        MouseArea {
                            id: handleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.SizeVerCursor
                            onPressed: {
                                root.dragFrom = row.index
                                root.dropBefore = row.index
                            }
                            onPositionChanged: mouse => {
                                if (root.dragFrom < 0) return
                                const p = mapToItem(list.contentItem, mouse.x, mouse.y)
                                const step = root.rowHeight + root.rowSpacing
                                root.dropBefore = Math.max(0, Math.min(list.count, Math.round(p.y / step)))
                            }
                            onReleased: {
                                const from = root.dragFrom
                                const before = root.dropBefore
                                root.dragFrom = -1
                                root.dropBefore = -1
                                if (from >= 0 && before !== from && before !== from + 1)
                                    root.player.playlistMove(from, before)
                            }
                            onCanceled: {
                                root.dragFrom = -1
                                root.dropBefore = -1
                            }
                        }
                    }

                    Icon {
                        id: mark
                        anchors.left: handle.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.current
                        iconName: "play"
                        size: 14
                        color: Theme.accent
                    }
                    Text {
                        id: number
                        anchors.left: handle.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        visible: !row.current
                        horizontalAlignment: Text.AlignHCenter
                        text: row.index + 1
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.features: { "tnum": 1 }
                    }

                    Text {
                        anchors.left: number.right
                        anchors.leftMargin: 12
                        anchors.right: removeButton.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.title || Theme.sourceName(row.modelData.source)
                        color: row.current ? Theme.text : Theme.text2
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: row.current ? Theme.bold : Font.Normal
                        elide: Text.ElideMiddle
                    }

                    IconButton {
                        id: removeButton
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        // Текущий не убираем — для этого есть «открыть другое»
                        visible: !row.current
                        opacity: row.hovered ? 1 : 0
                        enabled: row.hovered
                        implicitWidth: 32
                        implicitHeight: 32
                        iconName: "close"
                        iconSize: 14
                        restColor: Theme.text2
                        onClicked: root.player.playlistRemove(row.index)
                    }
                }
            }

            // Куда встанет перетаскиваемая запись
            Rectangle {
                parent: list.contentItem
                visible: root.dragFrom >= 0 && root.dropBefore !== root.dragFrom
                         && root.dropBefore !== root.dragFrom + 1
                x: 8
                // Над первой строкой — у самого края, иначе обрежется
                y: Math.max(0, root.dropBefore * (root.rowHeight + root.rowSpacing) - height / 2 - root.rowSpacing / 2)
                width: list.width - 16
                height: 2
                radius: 1
                color: Theme.accent
            }

            Text {
                parent: list  // дети ListView по умолчанию уходят в прокручиваемый contentItem
                anchors.centerIn: parent
                visible: list.count === 0
                text: "Очередь пуста"
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 13
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.margins: 16
            Layout.topMargin: 8
            text: "Перетащите за ручку, чтобы поменять порядок. Shift+N / Shift+P — следующее / предыдущее"
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
}
