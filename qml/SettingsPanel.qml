pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Настройки — модалка по центру: слева разделы, справа карточки раздела
// в стиле «Достижений» Bloom (.ach-card). Последний раздел запоминается.
Popup {
    id: root

    required property MpvObject player
    required property YtDlp ytdlp
    required property var prefs

    property string ytdlpMessage: ""
    // 0 — карточка на месте, 1 — уехала за правый край (как ModalDialog)
    property real slide: 1

    readonly property var sections: [
        { title: "Оформление",      icon: "palette" },
        { title: "Воспроизведение", icon: "speed" },
        { title: "Видео",           icon: "video" },
        { title: "yt-dlp",          icon: "download" },
        { title: "Горячие клавиши", icon: "keyboard" }
    ]
    readonly property int section: Math.max(0, Math.min(sections.length - 1, prefs.settingsSection))

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: Math.min(860, parent.width - 48)
    height: Math.min(580, parent.height - 48)
    x: Math.round((parent.width - width) / 2 + slide * (parent.width / 2 + width / 2 + 24))
    y: Math.round((parent.height - height) / 2)

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
        implicitWidth: Math.max(22, keyText.implicitWidth + 14)
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

    // Пункт навигации слева
    component NavButton: AbstractButton {
        id: nav
        required property var modelData
        required property int index
        readonly property bool selected: root.section === index

        Layout.fillWidth: true
        implicitHeight: 38
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        onClicked: root.prefs.settingsSection = index

        background: Rectangle {
            radius: Theme.radiusSm
            color: nav.selected ? Theme.film(0.07) : nav.hovered ? Theme.film(0.04) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        contentItem: Item {
            Icon {
                id: navIcon
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                iconName: nav.modelData.icon
                size: 17
                color: nav.selected ? Theme.accent : nav.hovered ? Theme.text : Theme.text2
            }
            Text {
                anchors.left: navIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: nav.modelData.title
                color: nav.selected || nav.hovered ? Theme.text : Theme.text2
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: nav.selected ? Theme.bold : Font.Normal
                elide: Text.ElideRight
            }
        }
    }

    // Страница раздела: прокручиваемая колонка карточек
    component SectionPage: Flickable {
        id: page
        default property alias cards: column.data
        contentHeight: column.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            x: 20
            y: 4
            width: page.width - 40
            spacing: 10
        }
    }

    // Группа горячих клавиш: [[[клавиши], "что делают"], …]
    component KeyGroup: Rectangle {
        id: group
        property string title: ""
        property var keys: []

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: groupColumn.implicitHeight + 26
        radius: Theme.radius
        color: "transparent"
        border.color: Theme.line

        ColumnLayout {
            id: groupColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 13
                leftMargin: 14
                rightMargin: 14
            }
            spacing: 7

            Text {
                text: group.title
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Theme.bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.7
                bottomPadding: 2
            }
            Repeater {
                model: group.keys
                delegate: RowLayout {
                    id: keyRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10

                    Row {
                        Layout.preferredWidth: 92
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
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    // --- Содержимое ---

    contentItem: RowLayout {
        spacing: 0

        // Навигация
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 200
            topLeftRadius: Theme.radius
            bottomLeftRadius: Theme.radius
            color: Theme.film(0.02)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                anchors.topMargin: 16
                spacing: 2

                Text {
                    Layout.leftMargin: 10
                    Layout.bottomMargin: 12
                    text: "Настройки"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Theme.bold
                    font.letterSpacing: -0.3
                }
                Repeater {
                    model: root.sections
                    delegate: NavButton {}
                }
                Item { Layout.fillHeight: true }
                Text {
                    Layout.leftMargin: 10
                    Layout.bottomMargin: 4
                    text: "WPlayer " + Qt.application.version
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Theme.bold
                }
            }

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.line
            }
        }

        // Раздел
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 8
                Layout.topMargin: 12
                Layout.bottomMargin: 10

                Text {
                    Layout.fillWidth: true
                    text: root.sections[root.section].title
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Theme.bold
                    font.letterSpacing: -0.3
                    elide: Text.ElideRight
                }
                IconButton {
                    iconName: "close"
                    iconSize: 16
                    restColor: Theme.text2
                    onClicked: root.close()
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.section

                // --- Оформление ---
                SectionPage {
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
                }

                // --- Воспроизведение ---
                SectionPage {
                    SettingCard {
                        Layout.fillWidth: true
                        iconName: "history"
                        title: "Продолжать с места"
                        description: "Недосмотренное видео откроется там, где вы остановились. Home — к началу"
                        on: root.prefs.resume
                        trailing: UiSwitch {
                            checked: root.prefs.resume
                            onToggled: root.prefs.resume = checked
                        }
                    }

                    SettingCard {
                        Layout.fillWidth: true
                        iconName: "queue"
                        title: "Следующие серии из папки"
                        description: "При открытии файла остальные видео из его папки встают в очередь по порядку"
                        on: root.prefs.autoloadFolder
                        trailing: UiSwitch {
                            checked: root.prefs.autoloadFolder
                            onToggled: {
                                root.prefs.autoloadFolder = checked
                                root.player.autoloadFolder = checked
                            }
                        }
                    }

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
                }

                // --- Видео ---
                SectionPage {
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
                }

                // --- yt-dlp ---
                SectionPage {
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
                        Hint {
                            text: "Нужен для страниц сайтов (YouTube и другие) и для звука из второй ссылки. Сайты меняются — если ссылка перестала открываться, обновите"
                        }
                    }
                }

                // --- Горячие клавиши ---
                SectionPage {
                    id: keysPage

                    GridLayout {
                        Layout.fillWidth: true
                        columns: keysPage.width >= 600 ? 2 : 1
                        columnSpacing: 10
                        rowSpacing: 10

                        KeyGroup {
                            title: "Воспроизведение"
                            keys: [
                                [["Space"], "Пауза"],
                                [["ЛКМ"], "Удерживать на видео — 2×"],
                                [["[", "]"], "Скорость − / +"],
                                [["⌫"], "Обычная скорость"],
                                [[",", "."], "Кадр назад / вперёд"]
                            ]
                        }
                        KeyGroup {
                            title: "Перемотка"
                            keys: [
                                [["←", "→"], "−5 / +5 с"],
                                [["Shift", "←→"], "−1 / +1 с"],
                                [["Ctrl", "→"], "+85 с — пропустить опенинг"],
                                [["PgUp", "PgDn"], "Предыдущая / следующая глава"],
                                [["Home"], "К началу видео"]
                            ]
                        }
                        KeyGroup {
                            title: "Звук и дорожки"
                            keys: [
                                [["↑", "↓"], "Громкость"],
                                [["M"], "Без звука"],
                                [["A"], "Следующая аудиодорожка"],
                                [["S"], "Следующие субтитры"],
                                [["Ctrl", "− ="], "Задержка аудио ∓50 мс"]
                            ]
                        }
                        KeyGroup {
                            title: "Очередь и окна"
                            keys: [
                                [["Shift", "N"], "Следующее в очереди"],
                                [["Shift", "P"], "Предыдущее в очереди"],
                                [["Q"], "Очередь"],
                                [["I"], "Инфо о видео"],
                                [["Ctrl", "H"], "История"],
                                [["F"], "Полный экран, Esc — выйти"]
                            ]
                        }
                        KeyGroup {
                            title: "Открыть"
                            keys: [
                                [["Ctrl", "O"], "Файл"],
                                [["Ctrl", "L"], "Ссылку"],
                                [["Ctrl", "⇧", "L"], "Видео + аудио"],
                                [["Ctrl", ","], "Настройки"]
                            ]
                        }
                        KeyGroup {
                            title: "Anime4K"
                            keys: [
                                [["Ctrl", "1…6"], "Режимы A … C+A"],
                                [["Ctrl", "0"], "Выключить"]
                            ]
                        }
                    }
                }
            }
        }
    }

    ColorPicker {
        id: colorPicker
        onPicked: hex => root.prefs.accent = hex
    }
}
