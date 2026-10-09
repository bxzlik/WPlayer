pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Управление поверх видео — раскладка как у плеера anibloom:
//   по центру кадра  — −10 / пауза / +10 на круглых подложках;
//   над полосой      — громкость слева, время по центру, иконки справа;
//   в самом низу     — полоса перемотки на всю ширину.
// Отдельной плашки нет: читаемость даёт затемнение у нижнего края кадра.
Item {
    id: root

    required property MpvObject player
    property bool fullscreen: false
    // Вместо длительности показывать, сколько осталось
    property bool showRemaining: false

    signal toggleFullscreen()
    signal openSettings()
    signal addAudioFile()
    signal addAudioUrl()
    signal addSubtitleFile()
    signal openQueue()

    // Пока true, управление не должно автоматически скрываться
    readonly property bool busy: bottomHover.hovered || centerHover.hovered
                                 || seekBar.pressed || volumeSlider.pressed
                                 || audioPopup.opened || subtitlePopup.opened
                                 || shaderPopup.opened || delayPopup.opened || speedPopup.opened

    // Затемнение у нижнего края (как _EdgeScrim в anibloom: от 62% высоты до
    // 72% черноты у края). Верх затемняет тайтлбар.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.38
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
        }
    }

    // Кнопка на круглой подложке по центру кадра
    component CenterButton: AbstractButton {
        id: centerButton
        property string iconName: ""
        property int iconSize: 30
        property int diameter: iconSize + 20
        implicitWidth: diameter
        implicitHeight: diameter
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        background: Rectangle {
            radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.45)
            scale: centerButton.down ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
        }
        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                iconName: centerButton.iconName
                size: centerButton.iconSize
                color: centerButton.hovered ? Theme.text : Theme.iconFg
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
    }

    // Иконка ряда над полосой: 34 px, значок 18 px, без подложки и подсказок
    component BarButton: IconButton {
        implicitWidth: label !== "" ? Math.max(34, labelWidth + 16) : 34
        implicitHeight: 34
        iconSize: 18
    }

    // --- Центр кадра ---
    // По краям — предыдущая / следующая глава (только если они есть в файле),
    // как кнопки глав в OSC mpv
    Row {
        anchors.centerIn: parent
        spacing: 26

        HoverHandler { id: centerHover }

        CenterButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.player.chapters.length > 0
            iconName: "fast-back"
            iconSize: 20
            onClicked: root.player.seekChapter(-1)
        }

        CenterButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "rewind"
            onClicked: root.player.seekRelative(-10)
        }

        Item {
            width: 68
            height: 68

            CenterButton {
                anchors.fill: parent
                visible: !root.player.buffering
                diameter: 68
                iconName: root.player.paused ? "play" : "pause"
                onClicked: root.player.togglePause()
            }
            // Пока поток догружается, на месте паузы — индикатор
            BusyIndicator {
                anchors.centerIn: parent
                width: 44
                height: 44
                running: root.player.buffering
                visible: running
            }
        }

        CenterButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "forward"
            onClicked: root.player.seekRelative(10)
        }

        CenterButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.player.chapters.length > 0
            iconName: "fast-forward"
            iconSize: 20
            onClicked: root.player.seekChapter(1)
        }
    }

    // --- Низ кадра ---
    Column {
        id: bottomArea
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 12
            rightMargin: 12
            bottomMargin: 8
        }

        HoverHandler { id: bottomHover }

        // Ряд над полосой. Собран стопкой, а не строкой: время должно стоять
        // ровно по центру, независимо от ширины боков.
        Item {
            width: parent.width
            height: 36

            // Очередь: предыдущее / следующее (если в ней больше одного) и список
            Row {
                id: queueRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool multiple: root.player.playlist.length > 1

                BarButton {
                    visible: queueRow.multiple
                    enabled: root.player.playlistPos > 0
                    iconName: "prev"
                    iconSize: 16
                    onClicked: root.player.playlistPrev()
                }
                BarButton {
                    visible: queueRow.multiple
                    enabled: root.player.playlistPos < root.player.playlist.length - 1
                    iconName: "next"
                    iconSize: 16
                    onClicked: root.player.playlistNext()
                }
                BarButton {
                    iconName: "queue"
                    active: queueRow.multiple
                    label: queueRow.multiple ? (root.player.playlistPos + 1) + " / " + root.player.playlist.length : ""
                    onClicked: root.openQueue()
                }
            }

            // Громкость: иконка, ползунок выезжает при наведении
            Row {
                id: volumeRow
                anchors.left: queueRow.right
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool expanded: volumeHover.hovered || volumeSlider.pressed

                HoverHandler { id: volumeHover }

                BarButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: Theme.volumeIcon(root.player.volume, root.player.muted)
                    onClicked: root.player.muted = !root.player.muted
                }
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: volumeRow.expanded ? 100 : 0
                    height: 32
                    clip: true
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    // Как в anibloom: дорожка 3 px (белая / 24%), ручка 10 px
                    // видна всегда, без подсветки вокруг
                    Slider {
                        id: volumeSlider
                        readonly property color fill: root.player.muted ? Theme.muted : Theme.text
                        x: 4
                        width: 92
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter
                        padding: 0
                        focusPolicy: Qt.NoFocus
                        from: 0
                        to: 100
                        value: root.player.volume
                        onMoved: {
                            root.player.volume = Math.round(value)
                            if (root.player.muted) root.player.muted = false
                        }

                        background: Item {
                            x: volumeSlider.leftPadding
                            y: volumeSlider.topPadding + (volumeSlider.availableHeight - height) / 2
                            width: volumeSlider.availableWidth
                            height: 3

                            Rectangle {
                                anchors.fill: parent
                                radius: 1.5
                                color: Theme.film(0.24)
                            }
                            Rectangle {
                                width: volumeSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 1.5
                                color: volumeSlider.fill
                            }
                        }

                        handle: Rectangle {
                            x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                            y: volumeSlider.topPadding + (volumeSlider.availableHeight - height) / 2
                            width: 10
                            height: 10
                            radius: 5
                            color: volumeSlider.fill
                        }
                    }
                }
            }

            // Время ровно по центру; нажатие — длительность ↔ остаток.
            // В узком окне сдвигается, чтобы не наезжать на иконки.
            AbstractButton {
                id: timeButton
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(volumeRow.x + volumeRow.width + 8, Math.min((parent.width - width) / 2, iconRow.x - width - 8))
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                padding: 4
                leftPadding: 8
                rightPadding: 8
                onClicked: root.showRemaining = !root.showRemaining

                readonly property real shownPosition: seekBar.pressed ? seekBar.value : root.player.position

                background: Item {}
                contentItem: Text {
                    text: Theme.formatTime(timeButton.shownPosition) + " / "
                          + (root.showRemaining
                             ? "−" + Theme.formatTime(Math.max(0, root.player.duration - timeButton.shownPosition))
                             : Theme.formatTime(root.player.duration))
                    color: timeButton.hovered ? Theme.text : Theme.iconFg
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Theme.bold
                    font.features: { "tnum": 1 }
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }

            // Иконки справа
            Row {
                id: iconRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                // Пропуск опенинга — на виду, а не в меню (как в anibloom)
                BarButton {
                    iconName: "skip-op"
                    onClicked: root.player.seekRelative(85)
                }
                BarButton {
                    id: speedButton
                    readonly property bool changed: Math.abs(root.player.speed - 1) >= 0.001
                    iconName: "speed"
                    label: changed ? Theme.formatSpeed(root.player.speed) : ""
                    active: changed
                    onClicked: speedPopup.toggleAbove(speedButton)
                }
                BarButton {
                    id: delayButton
                    readonly property bool shifted: Math.abs(root.player.audioDelay) >= 0.0005
                    iconName: "timer"
                    label: shifted ? Theme.formatDelay(root.player.audioDelay) : ""
                    active: shifted
                    onClicked: delayPopup.toggleAbove(delayButton)
                }
                BarButton {
                    id: audioButton
                    iconName: "audio"
                    onClicked: audioPopup.toggleAbove(audioButton)
                }
                BarButton {
                    id: subtitleButton
                    iconName: "subtitles"
                    active: root.player.subtitleId >= 0
                    onClicked: subtitlePopup.toggleAbove(subtitleButton)
                }
                BarButton {
                    id: shaderButton
                    iconName: "magic"
                    active: root.player.shaderPreset !== "off"
                    onClicked: shaderPopup.toggleAbove(shaderButton)
                }
                BarButton {
                    iconName: "settings"
                    onClicked: root.openSettings()
                }
                BarButton {
                    iconName: root.fullscreen ? "fullscreen-exit" : "fullscreen"
                    onClicked: root.toggleFullscreen()
                }
            }
        }

        // Полоса перемотки на всю ширину
        SeekBar {
            id: seekBar
            width: parent.width
            playbackPosition: root.player.position
            duration: root.player.duration
            cachedUntil: root.player.cachedUntil
            chapters: root.player.chapters
            onSeekRequested: (seconds, exact) => root.player.seek(seconds, exact)
        }
    }

    // --- Всплывающие меню ---

    ChoicePopup {
        id: audioPopup
        title: "Аудио"
        model: [{ value: -1, label: "Выключено", selected: root.player.audioId < 0 }]
               .concat(root.player.audioTracks.map(t => ({
                   value: t.id, label: t.label, detail: t.detail, selected: t.id === root.player.audioId
               })))
               .concat([
                   { value: "file", label: "Добавить из файла…", icon: "folder" },
                   { value: "url", label: "Добавить по ссылке…", icon: "link" }
               ])
        onChosen: value => {
            if (value === "file") root.addAudioFile()
            else if (value === "url") root.addAudioUrl()
            else root.player.setAudioTrack(value)
        }
    }

    ChoicePopup {
        id: subtitlePopup
        title: "Субтитры"
        model: [{ value: -1, label: "Выключено", selected: root.player.subtitleId < 0 }]
               .concat(root.player.subtitleTracks.map(t => ({
                   value: t.id, label: t.label, detail: t.detail, selected: t.id === root.player.subtitleId
               })))
               .concat([{ value: "file", label: "Добавить из файла…", icon: "folder" }])
        onChosen: value => {
            if (value === "file") root.addSubtitleFile()
            else root.player.setSubtitleTrack(value)
        }
    }

    ChoicePopup {
        id: shaderPopup
        title: root.player.anime4kFast ? "Anime4K · быстрый режим" : "Anime4K"
        width: 320
        model: Theme.anime4kModes.map(m => ({
            value: m.value, label: m.name, detail: m.value === "off" ? "" : m.detail,
            selected: m.value === root.player.shaderPreset
        }))
        onChosen: value => root.player.setShaderPreset(value)
    }

    ChoicePopup {
        id: speedPopup
        title: "Скорость"
        width: 200
        model: Theme.speeds.map(s => ({
            value: s, label: s === 1 ? "Обычная" : Theme.formatSpeed(s),
            selected: Math.abs(s - root.player.speed) < 0.001
        }))
        onChosen: value => root.player.speed = value
    }

    FloatingPopup {
        id: delayPopup
        width: 330
        padding: 14

        contentItem: ColumnLayout {
            spacing: 12

            RowLayout {
                Text {
                    text: "Задержка аудио"
                    color: Theme.text2
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Theme.bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.7
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: Theme.formatDelay(root.player.audioDelay)
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Theme.bold
                }
            }

            FlatSlider {
                Layout.fillWidth: true
                from: -5
                to: 5
                value: root.player.audioDelay
                onMoved: root.player.audioDelay = Math.round(value * 100) / 100
            }

            RowLayout {
                spacing: 6
                Repeater {
                    model: [-0.1, -0.01, 0.01, 0.1]
                    delegate: PillButton {
                        id: stepButton
                        required property real modelData
                        compact: true
                        Layout.fillWidth: true
                        text: (modelData > 0 ? "+" : "−") + Math.round(Math.abs(modelData) * 1000)
                        onClicked: root.player.audioDelay =
                                   Math.round((root.player.audioDelay + stepButton.modelData) * 1000) / 1000
                    }
                }
                PillButton {
                    compact: true
                    Layout.fillWidth: true
                    text: "Сброс"
                    onClicked: root.player.audioDelay = 0
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Шаг в миллисекундах. Плюс — звук позже, минус — раньше. Ctrl+− / Ctrl+= — ±50 мс"
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 11
            }
        }
    }
}
