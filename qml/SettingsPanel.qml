pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Шторка настроек в стиле «Достижений» Bloom (.spanel): плавающая карточка
// справа поверх затемнения, шапка «название + плашка», ниже колонка карточек.
Popup {
    id: root

    required property MpvObject player
    required property YtDlp ytdlp
    required property var prefs

    property string ytdlpMessage: ""
    // 0 — шторка на месте, 1 — уехала за правый край
    property real slide: 1

    // В полном экране кнопок окна нет — шторка встаёт под самый верх,
    // как в Bloom (--tb-h: 0 в fullscreen)
    property bool fullscreen: false
    property real panelTop: (fullscreen ? 0 : 32) + 16
    Behavior on panelTop { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: Math.min(420, parent.width - 32)
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

    Connections {
        target: root.ytdlp
        function onUpdateFinished(ok, message) { root.ytdlpMessage = message }
    }

    // --- Мелкие элементы ---

    component Badge: Rectangle {
        property alias text: badgeText.text
        implicitWidth: badgeText.implicitWidth + 20
        implicitHeight: badgeText.implicitHeight + 6
        radius: height / 2
        color: "transparent"
        border.color: Theme.line
        Text {
            id: badgeText
            anchors.centerIn: parent
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Theme.bold
        }
    }

    component Hint: Text {
        Layout.fillWidth: true
        color: Theme.muted
        font.family: Theme.font
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    component Swatch: AbstractButton {
        id: swatch
        property color swatchColor: "transparent"
        property bool selected: false
        property string iconName: ""
        implicitWidth: 30
        implicitHeight: 30
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        background: Rectangle {
            radius: Theme.radius * 0.4
            color: swatch.swatchColor
            border.width: 2
            border.color: swatch.selected ? Theme.text
                        : swatch.hovered ? Theme.film(0.25) : Theme.border
            Behavior on border.color { ColorAnimation { duration: 150 } }
        }
        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                visible: swatch.iconName !== "" || swatch.selected
                iconName: swatch.iconName !== "" ? swatch.iconName : "check"
                size: 14
                color: swatch.iconName !== "" ? Theme.text2
                     : (Theme.luminance(swatch.swatchColor) > 0.55 ? "#000000" : "#ffffff")
            }
        }
    }

    component Key: Rectangle {
        property alias text: keyText.text
        implicitWidth: keyText.implicitWidth + 14
        implicitHeight: 22
        radius: 6
        color: Theme.film(0.05)
        border.color: Theme.line
        Text {
            id: keyText
            anchors.centerIn: parent
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 11
            font.weight: Theme.bold
        }
    }

    // --- Содержимое ---

    contentItem: ColumnLayout {
        spacing: 0

        // Шапка: название слева, плашка и закрытие справа
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 8
            Layout.topMargin: 12
            Layout.bottomMargin: 8
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: "Настройки"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 17
                font.weight: Theme.bold
                font.letterSpacing: -0.3
                elide: Text.ElideRight
            }
            Badge { text: "v" + Qt.application.version }
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
            contentHeight: cards.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: cards
                x: 16
                y: 8
                width: flick.width - 32
                spacing: 10

                // --- Цвет акцента ---
                SettingCard {
                    Layout.fillWidth: true
                    iconName: "palette"
                    title: "Цвет акцента"
                    description: "Кнопки, ползунки и активные иконки"

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: Theme.accentPresets
                            delegate: Swatch {
                                required property string modelData
                                swatchColor: modelData
                                selected: Qt.colorEqual(modelData, Theme.accent)
                                onClicked: root.prefs.accent = modelData
                            }
                        }
                        Swatch {
                            id: customSwatch
                            readonly property bool isCustom: !Theme.accentPresets.some(c => Qt.colorEqual(c, Theme.accent))
                            swatchColor: isCustom ? Theme.accent : "transparent"
                            selected: isCustom
                            iconName: isCustom ? "" : "plus"
                            onClicked: colorPicker.openFor(customSwatch, Theme.accent)
                        }
                    }
                }

                // --- Anime4K ---
                SettingCard {
                    Layout.fillWidth: true
                    iconName: "magic"
                    title: "Anime4K"
                    on: root.player.shaderPreset !== "off"
                    description: Theme.anime4kMode(root.player.shaderPreset).detail

                    Segmented {
                        Layout.maximumWidth: parent.width
                        options: Theme.anime4kModes.map(m => ({ value: m.value, label: m.label }))
                        current: root.player.shaderPreset
                        onPicked: value => root.player.setShaderPreset(value)
                    }
                    Hint {
                        text: "Шейдеры берутся из папки shaders рядом с WPlayer.exe. Ctrl+1…6 — режимы, Ctrl+0 — выключить"
                    }
                }

                SettingCard {
                    Layout.fillWidth: true
                    iconName: "bolt"
                    title: "Быстрый Anime4K"
                    description: "Облегчённые модели для слабых видеокарт и ноутбуков"
                    on: root.player.anime4kFast
                    trailing: UiSwitch {
                        checked: root.player.anime4kFast
                        onToggled: {
                            root.player.anime4kFast = checked
                            root.prefs.anime4kFast = checked
                        }
                    }
                }

                // --- Видео ---
                SettingCard {
                    Layout.fillWidth: true
                    iconName: "cpu"
                    title: "Аппаратное декодирование"
                    description: "Видео декодирует видеокарта — меньше нагрузка на процессор"
                    on: root.player.hwdec
                    trailing: UiSwitch {
                        checked: root.player.hwdec
                        onToggled: {
                            root.player.hwdec = checked
                            root.prefs.hwdec = checked
                        }
                    }
                }

                // --- Языки ---
                SettingCard {
                    Layout.fillWidth: true
                    iconName: "language"
                    title: "Языки дорожек"
                    description: "Коды через запятую, по приоритету. Применяются к следующему файлу"
                    on: root.prefs.alang !== "" || root.prefs.slang !== ""

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        UiTextField {
                            Layout.fillWidth: true
                            capsule: true
                            text: root.prefs.alang
                            placeholderText: "Аудио: jpn,ja"
                            onEditingFinished: {
                                root.prefs.alang = text
                                root.player.setMpvProperty("alang", text)
                            }
                        }
                        UiTextField {
                            Layout.fillWidth: true
                            capsule: true
                            text: root.prefs.slang
                            placeholderText: "Субтитры: rus,eng"
                            onEditingFinished: {
                                root.prefs.slang = text
                                root.player.setMpvProperty("slang", text)
                            }
                        }
                    }
                }

                // --- yt-dlp ---
                SettingCard {
                    Layout.fillWidth: true
                    iconName: "download"
                    title: "yt-dlp"
                    on: root.ytdlp.version !== ""
                    description: root.ytdlp.version === ""
                                 ? "Не найден — нужен для ссылок на сайты"
                                 : "Версия " + root.ytdlp.version
                                   + (root.ytdlp.bundled ? " · рядом с программой" : " · из PATH")
                    trailing: PillButton {
                        compact: true
                        iconName: root.ytdlp.bundled ? "refresh" : "download"
                        text: root.ytdlp.bundled ? "Обновить" : "Скачать"
                        enabled: !root.ytdlp.busy
                        onClicked: {
                            root.ytdlpMessage = ""
                            root.ytdlp.update()
                        }
                    }

                    // Полоса как .ach-bar; пока идёт обновление — бегущая
                    Rectangle {
                        id: busyTrack
                        visible: root.ytdlp.busy
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: Theme.film(0.08)
                        clip: true

                        Rectangle {
                            width: busyTrack.width * 0.35
                            height: parent.height
                            radius: 3
                            color: Theme.accent
                            NumberAnimation on x {
                                running: root.ytdlp.busy
                                loops: Animation.Infinite
                                from: -busyTrack.width * 0.35
                                to: busyTrack.width
                                duration: 1100
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                    Hint {
                        visible: root.ytdlpMessage !== ""
                        text: root.ytdlpMessage
                    }
                }

                // --- Горячие клавиши ---
                SettingCard {
                    Layout.fillWidth: true
                    iconName: "keyboard"
                    title: "Горячие клавиши"

                    Repeater {
                        model: [
                            [["Space"], "Пауза"],
                            [["←", "→"], "−5 / +5 с"],
                            [["Ctrl", "→"], "+85 с — пропустить опенинг"],
                            [["PgUp", "PgDn"], "Предыдущая / следующая глава"],
                            [["[", "]"], "Скорость −/+, Backspace — обычная"],
                            [["ЛКМ"], "Удерживать на видео — 2×"],
                            [[",", "."], "Кадр назад / вперёд"],
                            [["↑", "↓"], "Громкость"],
                            [["M"], "Без звука"],
                            [["F"], "Полный экран"],
                            [["A"], "Следующая аудиодорожка"],
                            [["S"], "Следующие субтитры"],
                            [["Ctrl", "−"], "Задержка аудио −50 мс"],
                            [["Ctrl", "1…6"], "Anime4K, Ctrl+0 — выкл"],
                            [["Ctrl", "O"], "Открыть файл"],
                            [["Ctrl", "L"], "Открыть ссылку"]
                        ]
                        delegate: RowLayout {
                            id: keyRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10

                            Row {
                                Layout.preferredWidth: 96
                                spacing: 4
                                Repeater {
                                    model: keyRow.modelData[0]
                                    delegate: Key {
                                        required property string modelData
                                        text: modelData
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: keyRow.modelData[1]
                                color: Theme.text2
                                font.family: Theme.font
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // --- О программе ---
                SettingCard {
                    Layout.fillWidth: true
                    iconName: "info"
                    title: "WPlayer"
                    trailing: Badge { text: Qt.application.version }
                }
            }
        }
    }

    ColorPicker {
        id: colorPicker
        onPicked: hex => root.prefs.accent = hex
    }
}
