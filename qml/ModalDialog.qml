pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts

// Центральная модалка в стиле Bloom (.mover + .modal): подложка .55 с размытием,
// карточка цвета блока без рамки выезжает из-за правой кромки окна,
// внизу — ряд кнопок на всю ширину.
Popup {
    id: root

    property string title: ""
    property string subtitle: ""
    // Что размывать под подложкой (обычно contentItem окна)
    property Item blurSource: null

    default property alias content: body.data
    property alias buttons: footerRow.data

    // 0 — карточка на месте, 1 — уехала за правый край
    property real slide: 1

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: Math.min(400, parent.width - 32)
    x: Math.round((parent.width - width) / 2 + slide * (parent.width / 2 + width / 2 + 24))
    y: Math.round((parent.height - height) / 2)

    Overlay.modal: Item {
        Behavior on opacity { NumberAnimation { duration: 220 } }

        ShaderEffectSource {
            id: blurSourceItem
            anchors.fill: parent
            sourceItem: root.blurSource
            visible: false
            live: true
        }
        MultiEffect {
            anchors.fill: parent
            visible: root.blurSource !== null
            source: blurSourceItem
            blurEnabled: true
            blur: 1.0
            blurMax: 32
        }
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
        }
    }

    enter: Transition {
        NumberAnimation {
            property: "slide"
            from: 1
            to: 0
            duration: Theme.slideDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.slideCurve
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "slide"
            from: 0
            to: 1
            duration: Theme.slideDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.slideCurve
        }
    }

    background: Rectangle {
        color: Theme.surface
        radius: Theme.radius
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.9)
            shadowBlur: 1.0
            shadowVerticalOffset: 24
            autoPaddingEnabled: true
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 10
            Layout.topMargin: 16
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Theme.bold
                    font.letterSpacing: -0.3
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    color: Theme.text2
                    font.family: Theme.font
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            IconButton {
                Layout.alignment: Qt.AlignTop
                iconName: "close"
                iconSize: 16
                restColor: Theme.text2
                onClicked: root.close()
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.topMargin: 16
            spacing: 10
        }

        RowLayout {
            id: footerRow
            Layout.fillWidth: true
            Layout.margins: 16
            Layout.topMargin: 20
            spacing: 10
        }
    }
}
