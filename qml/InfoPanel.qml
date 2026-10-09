pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Сведения о текущем файле — шторка справа, как настройки: карточки
// «Файл / Видео / Аудио / Субтитры» со строками «название — значение».
Popup {
    id: root

    required property MpvObject player

    // [{ title, icon, rows: [{ label, value }] }] из MpvObject::mediaInfo
    property var sections: []
    property real slide: 1

    property bool fullscreen: false
    property real panelTop: (fullscreen ? 0 : 32) + 16
    Behavior on panelTop { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    function refresh() {
        const next = player.mediaInfo()
        // Пересобираем карточки, только если что-то поменялось
        if (JSON.stringify(next) !== JSON.stringify(sections))
            sections = next
    }

    function asText() {
        return sections.map(s => s.title + "\n" + s.rows.map(r => "  " + r.label + ": " + r.value).join("\n"))
                       .join("\n\n")
    }

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: Math.min(420, parent.width - 32)
    height: Math.min(parent.height - panelTop - 16, layout.implicitHeight)
    x: Math.round(parent.width - width - 16 + slide * (width + 40))
    // По вертикали — посередине; длинная шторка упирается в верхний отступ
    y: Math.max(panelTop, Math.round((parent.height - height) / 2))

    onAboutToShow: refresh()

    // Битрейт и декодирование могут меняться по ходу — подновляем
    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        onTriggered: root.refresh()
    }

    Connections {
        target: root.player
        function onIdleChanged() { if (root.player.idle) root.close() }
        function onFileLoaded() { if (root.visible) root.refresh() }
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

    // Буфер обмена в QML доступен только через текстовое поле
    TextEdit {
        id: clipboard
        visible: false
        function copyText(value) {
            text = value
            selectAll()
            copy()
        }
    }

    contentItem: ColumnLayout {
        id: layout
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
                text: "Инфо о видео"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 17
                font.weight: Theme.bold
                font.letterSpacing: -0.3
                elide: Text.ElideRight
            }
            PillButton {
                id: copyButton
                compact: true
                text: copiedTimer.running ? "Скопировано" : "Копировать"
                onClicked: {
                    clipboard.copyText(root.asText())
                    copiedTimer.restart()
                }
                Timer { id: copiedTimer; interval: 1500 }
            }
            IconButton {
                iconName: "close"
                iconSize: 16
                restColor: Theme.text2
                onClicked: root.close()
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: cards.implicitHeight + 24
            contentHeight: cards.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: cards
                x: 16
                y: 8
                width: flick.width - 32
                spacing: 10

                Repeater {
                    model: root.sections

                    delegate: SettingCard {
                        id: card
                        required property var modelData
                        Layout.fillWidth: true
                        iconName: modelData.icon
                        title: modelData.title

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 6

                            Repeater {
                                model: card.modelData.rows
                                delegate: Text {
                                    required property var modelData
                                    required property int index
                                    // Подписи — в первом столбце, значения — во втором
                                    Layout.preferredWidth: 104
                                    Layout.alignment: Qt.AlignTop
                                    text: modelData.label
                                    color: Theme.text2
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    Layout.row: index
                                    Layout.column: 0
                                }
                            }
                            Repeater {
                                model: card.modelData.rows
                                delegate: Text {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.row: index
                                    Layout.column: 1
                                    text: modelData.value
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    // Пути и ссылки переносим где угодно, остальное — по словам
                                    wrapMode: /[\\\/]/.test(modelData.value) ? Text.WrapAnywhere : Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
