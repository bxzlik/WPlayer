import QtQuick

// Полоса перемотки как в anibloom: 4 px, при наведении 6 px, без ручки.
// Слои: фон (24%), загруженная часть (38%), пройденная (акцент).
// Над курсором — подсказка со временем.
FlatSlider {
    id: root

    property real playbackPosition: 0
    property real duration: 0
    property real cachedUntil: 0

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
    }

    handle: Item {}

    Rectangle {
        id: tip
        // Пока тянут, наведение не обновляется (мышь захвачена полосой) —
        // подсказка идёт за точкой перетаскивания
        readonly property real hx: root.pressed ? root.visualPosition * root.width
                                                : Math.max(0, Math.min(root.hoverX, root.width))

        visible: (root.hovering || root.pressed) && root.duration > 0
        width: 64
        height: tipText.implicitHeight + 8
        x: Math.max(0, Math.min(hx - width / 2, root.width - width))
        y: -height - 2
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.82)

        Text {
            id: tipText
            anchors.centerIn: parent
            text: Theme.formatTime(tip.hx / Math.max(1, root.width) * root.duration)
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 11
            font.weight: Theme.bold
            font.features: { "tnum": 1 }
        }
    }
}
