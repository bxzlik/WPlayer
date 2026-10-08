pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// Список вариантов с галочкой у выбранного (дорожки, пресеты Anime4K)
FloatingPopup {
    id: root

    property string title: ""
    // [{ value, label, detail?, selected?, icon? }]
    property var model: []

    signal chosen(var value)

    width: 300

    contentItem: Column {
        spacing: 2

        Text {
            visible: root.title !== ""
            text: root.title
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 11
            font.weight: Theme.bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.7
            leftPadding: 10
            topPadding: 6
            bottomPadding: 6
        }

        Flickable {
            width: parent.width
            height: Math.min(list.implicitHeight, 380)
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.model

                    delegate: AbstractButton {
                        id: row
                        required property var modelData
                        readonly property bool hasDetail: !!row.modelData.detail
                        readonly property bool selected: !!row.modelData.selected

                        width: list.width
                        height: hasDetail ? 50 : 38
                        hoverEnabled: true
                        focusPolicy: Qt.NoFocus
                        onClicked: {
                            root.chosen(row.modelData.value)
                            root.close()
                        }

                        background: Rectangle {
                            radius: Theme.radiusSm
                            color: row.selected ? Theme.film(0.06)
                                 : row.hovered ? Theme.film(0.05) : "transparent"
                        }

                        contentItem: Item {
                            Icon {
                                id: lead
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                size: 16
                                iconName: row.modelData.icon ? row.modelData.icon : (row.selected ? "check" : "")
                                color: row.selected ? Theme.accent : Theme.text2
                            }

                            Column {
                                anchors.left: lead.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: row.modelData.label
                                    color: row.selected || row.hovered ? Theme.text : Theme.text2
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                    font.weight: row.selected ? Theme.bold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: row.hasDetail
                                    text: row.modelData.detail || ""
                                    color: Theme.muted
                                    font.family: Theme.font
                                    font.pixelSize: 11
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
