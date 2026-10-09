import QtQuick

// Полоса перемотки как в anibloom: 4 px, при наведении 6 px, без ручки.
// Слои: фон (24%), загруженная часть (38%), пройденная (акцент).
// Над курсором — подсказка со временем.
FlatSlider {
    id: root

    property real playbackPosition: 0
    property real duration: 0
    property real cachedUntil: 0
    // [{ title, time }] — у начала каждой главы на полосе разрыв
    property var chapters: []

    // Название главы, в которую попадает момент seconds
    function chapterTitleAt(seconds) {
        let title = ""
        for (let i = 0; i < chapters.length; ++i) {
            if (chapters[i].time > seconds) break
            title = chapters[i].title
        }
        return title
    }

    // exact = false во время перетаскивания (быстрый поиск по ключевым кадрам)
    signal seekRequested(real seconds, bool exact)

    from: 0
    to: duration > 0 ? duration : 1
    enabled: duration > 0
    implicitHeight: 20

    Binding on value {
        when: !root.pressed
        value: root.playbackPosition
        restoreMode: Binding.RestoreNone
    }

    onMoved: seekRequested(value, false)
    onPressedChanged: if (!pressed && duration > 0) seekRequested(value, true)

    background: Item {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.availableWidth
        height: root.active ? 6 : 4
        Behavior on height { NumberAnimation { duration: 120 } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.film(0.24)
        }
        Rectangle {
            width: root.duration > 0
                   ? Math.min(1, Math.max(0, root.cachedUntil / root.duration)) * parent.width : 0
            height: parent.height
            radius: height / 2
            color: Theme.film(0.38)
        }
        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: height / 2
            color: root.fillColor
        }

        // Разрывы на границах глав (первая глава с 0:00 разрыва не даёт)
        Repeater {
            model: root.duration > 0 ? root.chapters : []
            delegate: Rectangle {
                required property var modelData
                visible: modelData.time > 0 && modelData.time < root.duration
                x: modelData.time / root.duration * parent.width - width / 2
                width: 2
                height: parent.height
                color: Qt.rgba(0, 0, 0, 0.75)
            }
        }
    }

    handle: Item {}

    Rectangle {
        id: tip
        // Пока тянут, наведение не обновляется (мышь захвачена полосой) —
        // подсказка идёт за точкой перетаскивания
        readonly property real hx: root.pressed ? root.visualPosition * root.width
                                                : Math.max(0, Math.min(root.hoverX, root.width))

        readonly property real seconds: hx / Math.max(1, root.width) * root.duration
        readonly property string chapterTitle: root.chapterTitleAt(seconds)

        visible: (root.hovering || root.pressed) && root.duration > 0
        width: Math.max(64, Math.min(260, 16 + Math.max(timeText.implicitWidth,
                                                         chapterText.visible ? chapterText.implicitWidth : 0)))
        height: tipColumn.implicitHeight + 8
        x: Math.max(0, Math.min(hx - width / 2, root.width - width))
        y: -height - 2
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.82)

        Column {
            id: tipColumn
            anchors.centerIn: parent
            width: tip.width - 16

            Text {
                id: chapterText
                width: parent.width
                visible: tip.chapterTitle !== ""
                horizontalAlignment: Text.AlignHCenter
                text: tip.chapterTitle
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            Text {
                id: timeText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Theme.formatTime(tip.seconds)
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Theme.bold
                font.features: { "tnum": 1 }
            }
        }
    }
}
