pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Вся история — шторка справа, как настройки: поиск, список, очистка
Popup {
    id: root

    required property History history

    signal entryChosen(var entry)

    property real slide: 1
    property bool fullscreen: false
    property real panelTop: (fullscreen ? 0 : 32) + 16
    Behavior on panelTop { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // Очистка — в два нажатия: первое только спрашивает
    property bool confirmClear: false

    readonly property var shown: {
        const q = search.text.trim().toLowerCase()
        if (q === "") return history.entries
        return history.entries.filter(e => (e.title || "").toLowerCase().indexOf(q) >= 0
                                           || e.video.toLowerCase().indexOf(q) >= 0)
    }

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: Math.min(460, parent.width - 32)
    height: parent.height - panelTop - 16
    x: Math.round(parent.width - width - 16 + slide * (width + 40))
    y: panelTop

    onAboutToShow: {
        search.text = ""
        confirmClear = false
    }

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

    Timer {
        id: confirmTimer
        interval: 3000
        onTriggered: root.confirmClear = false
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
                Layout.fillWidth: true
                text: "История"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 17
                font.weight: Theme.bold
                font.letterSpacing: -0.3
                elide: Text.ElideRight
            }
            PillButton {
                compact: true
                visible: root.history.entries.length > 0
                text: root.confirmClear ? "Точно очистить?" : "Очистить"
                onClicked: {
                    if (root.confirmClear) {
                        root.history.clear()
                        root.confirmClear = false
                    } else {
                        root.confirmClear = true
                        confirmTimer.restart()
                    }
                }
            }
            IconButton {
                iconName: "close"
                iconSize: 16
                restColor: Theme.text2
                onClicked: root.close()
            }
        }

        UiTextField {
            id: search
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 8
            visible: root.history.entries.length > 0
            capsule: true
            placeholderText: "Поиск по названию или пути"
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 8
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.shown

            delegate: HistoryRow {
                required property var modelData
                width: list.width
                entry: modelData
                watched: root.history.finished(modelData)
                onClicked: {
                    root.entryChosen(modelData)
                    root.close()
                }
                onRemoveClicked: root.history.remove(modelData.video, modelData.audio)
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: root.history.entries.length === 0 ? "Здесь появится то, что вы смотрели" : "Ничего не найдено"
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 13
            }
        }
    }
}
