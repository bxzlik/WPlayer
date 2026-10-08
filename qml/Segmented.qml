pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// Сегмент-переключатель как .s-seg в Bloom: ряд вариантов в одной капсуле.
// Ширина — по содержимому (кнопка = подпись + 12 px по бокам), как inline-flex там.
Rectangle {
    id: root

    // [{ value, label }]
    property var options: []
    property var current
    signal picked(var value)

    implicitHeight: 32
    implicitWidth: row.implicitWidth
    width: implicitWidth
    radius: Theme.radius * 0.7
    color: "transparent"
    border.color: Theme.film(0.03)

    Row {
        id: row
        height: parent.height

        Repeater {
            model: root.options

            delegate: AbstractButton {
                id: seg
                required property var modelData
                required property int index
                readonly property bool selected: modelData.value === root.current
                readonly property bool first: index === 0
                readonly property bool last: index === root.options.length - 1
                // Скругление подложки внутри рамки (рамка — 1 px)
                readonly property real innerRadius: Math.max(0, root.radius - 1)

                height: root.height
                leftPadding: 12 + leftInset
                rightPadding: 12 + rightInset
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                onClicked: root.picked(modelData.value)

                // Подложка не заходит на рамку капсулы, а у крайних сегментов
                // повторяет её скругление — иначе углы торчат за линию
                topInset: 1
                bottomInset: 1
                leftInset: first ? 1 : 0
                rightInset: last ? 1 : 0

                background: Rectangle {
                    topLeftRadius: seg.first ? seg.innerRadius : 0
                    bottomLeftRadius: seg.first ? seg.innerRadius : 0
                    topRightRadius: seg.last ? seg.innerRadius : 0
                    bottomRightRadius: seg.last ? seg.innerRadius : 0
                    color: seg.selected ? Theme.film(0.16) : seg.hovered ? Theme.film(0.09) : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        visible: seg.index > 0
                        width: 1
                        height: parent.height
                        color: Theme.film(0.03)
                    }
                }

                contentItem: Text {
                    text: seg.modelData.label
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: seg.selected || seg.hovered ? Theme.text : Theme.text2
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Theme.bold
                    elide: Text.ElideRight
                }
            }
        }
    }
}
