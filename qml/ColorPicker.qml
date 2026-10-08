import QtQuick

// HSV-пикер как в Bloom (#cpPopup): поле насыщенности/яркости, полоса оттенка
// и поле для hex. Цвет отдаётся сразу, по ходу перетаскивания.
FloatingPopup {
    id: root

    property real hue: 0         // 0…360
    property real sat: 1         // 0…1
    property real val: 1         // 0…1
    readonly property string hex: hsv2hex(hue, sat, val)

    signal picked(string hex)

    width: 228
    padding: 12

    function openFor(item, color) {
        const hsv = hex2hsv(color.toString())
        hue = hsv.h
        sat = hsv.s
        val = hsv.v
        hexField.text = hex
        openBelow(item)
    }

    function apply(h, s, v) {
        hue = h
        sat = s
        val = v
        if (!hexField.activeFocus)
            hexField.text = hex
        picked(hex)
    }

    function hsv2hex(h, s, v) {
        const f = n => {
            const k = (n + h / 60) % 6
            return v - v * s * Math.max(0, Math.min(k, 4 - k, 1))
        }
        const to = x => {
            const s2 = Math.round(x * 255).toString(16)
            return s2.length < 2 ? "0" + s2 : s2
        }
        return "#" + to(f(5)) + to(f(3)) + to(f(1))
    }

    function hex2hsv(input) {
        let hex = input.replace(/[^0-9a-fA-F]/g, "")
        if (hex.length === 8) hex = hex.substring(2)  // #AARRGGBB из QML color
        if (hex.length === 3) hex = hex.split("").map(c => c + c).join("")
        if (hex.length !== 6) return { h: 0, s: 0, v: 1 }
        const r = parseInt(hex.substring(0, 2), 16) / 255
        const g = parseInt(hex.substring(2, 4), 16) / 255
        const b = parseInt(hex.substring(4, 6), 16) / 255
        const max = Math.max(r, g, b)
        const min = Math.min(r, g, b)
        const d = max - min
        let h = 0
        if (d > 0) {
            if (max === r) h = 60 * (((g - b) / d) % 6)
            else if (max === g) h = 60 * ((b - r) / d + 2)
            else h = 60 * ((r - g) / d + 4)
            if (h < 0) h += 360
        }
        return { h: h, s: max > 0 ? d / max : 0, v: max }
    }

    contentItem: Column {
        spacing: 10

        // Насыщенность (вправо) и яркость (вверх)
        Rectangle {
            id: satBox
            width: parent.width
            height: 140
            radius: 8
            color: Qt.hsva(root.hue / 360, 1, 1, 1)

            Rectangle {
                anchors.fill: parent
                radius: 8
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#ffffffff" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: 8
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 1.0; color: "#ff000000" }
                }
            }
            Rectangle {
                x: root.sat * parent.width - width / 2
                y: (1 - root.val) * parent.height - height / 2
                width: 14
                height: 14
                radius: 7
                color: "transparent"
                border.width: 2
                border.color: "white"
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                function update(mouse) {
                    root.apply(root.hue,
                               Math.max(0, Math.min(1, mouse.x / width)),
                               1 - Math.max(0, Math.min(1, mouse.y / height)))
                }
                onPressed: mouse => update(mouse)
                onPositionChanged: mouse => update(mouse)
            }
        }

        // Оттенок
        Rectangle {
            width: parent.width
            height: 12
            radius: 6
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;   color: "#ff0000" }
                GradientStop { position: 1 / 6; color: "#ffff00" }
                GradientStop { position: 2 / 6; color: "#00ff00" }
                GradientStop { position: 3 / 6; color: "#00ffff" }
                GradientStop { position: 4 / 6; color: "#0000ff" }
                GradientStop { position: 5 / 6; color: "#ff00ff" }
                GradientStop { position: 1.0;   color: "#ff0000" }
            }

            Rectangle {
                x: root.hue / 360 * parent.width - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: Qt.hsva(root.hue / 360, 1, 1, 1)
                border.width: 2
                border.color: "white"
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                preventStealing: true
                function update(mouse) {
                    root.apply(Math.max(0, Math.min(360, (mouse.x - 6) / (width - 12) * 360)), root.sat, root.val)
                }
                onPressed: mouse => update(mouse)
                onPositionChanged: mouse => update(mouse)
            }
        }

        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                width: 38
                height: 38
                radius: Theme.radiusSm
                color: root.hex
                border.color: Theme.line2
            }
            UiTextField {
                id: hexField
                width: parent.width - 46
                maximumLength: 7
                placeholderText: "#ffffff"
                onTextEdited: {
                    let v = text.trim()
                    if (!v.startsWith("#")) v = "#" + v
                    if (/^#[0-9a-fA-F]{6}$/.test(v)) {
                        const hsv = root.hex2hsv(v)
                        root.apply(hsv.h, hsv.s, hsv.v)
                    }
                }
                onEditingFinished: text = root.hex
                onAccepted: root.close()
            }
        }
    }
}
