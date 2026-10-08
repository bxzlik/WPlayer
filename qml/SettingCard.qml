import QtQuick
import QtQuick.Layouts

// Карточка настройки по образцу карточки достижения Bloom (.ach-card):
// «медаль» с иконкой слева, название и описание, справа — переключатель или
// кнопка, ниже — дополнительные элементы. on — «достижение взято»: медаль
// подсвечивается акцентом (настройка включена).
Rectangle {
    id: root

    property string iconName: ""
    property string title: ""
    property string description: ""
    property bool on: true

    default property alias content: extra.data
    property alias trailing: trailingSlot.data

    implicitHeight: layout.implicitHeight + 26
    radius: Theme.radius
    color: "transparent"
    border.color: hover.hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.line
    Behavior on border.color { ColorAnimation { duration: 200 } }

    HoverHandler { id: hover }

    RowLayout {
        id: layout
        anchors {
            fill: parent
            topMargin: 13
            bottomMargin: 13
            leftMargin: 14
            rightMargin: 14
        }
        spacing: 12

        // Медаль
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 42
            implicitHeight: 42
            radius: 12
            color: root.on ? Theme.accentSoft : Theme.film(0.05)
            border.color: root.on ? Theme.accentLine : Theme.line
            Behavior on color { ColorAnimation { duration: 200 } }

            Icon {
                anchors.centerIn: parent
                iconName: root.iconName
                size: 20
                color: root.on ? Theme.accent : Theme.muted
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumHeight: 22
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Theme.bold
                    elide: Text.ElideRight
                }
                Row {
                    id: trailingSlot
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.description !== ""
                text: root.description
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                id: extra
                Layout.fillWidth: true
                Layout.topMargin: visibleChildren.length > 0 ? 6 : 0
                spacing: 8
            }
        }
    }
}
