import QtQuick
import QtQuick.Controls

// Кнопка окна как .win-btn в Bloom: 32×32, без подложки, на наведении светлеет
// иконка; у «закрыть» она краснеет.
AbstractButton {
    id: root

    property string iconName: ""
    property int iconSize: 14
    property bool closeButton: false
    // Для «развернуть» наведение и нажатие приходят из WindowChrome,
    // потому что над ней Windows показывает Snap Layouts
    property bool externalHover: false
    property bool externalPress: false

    readonly property bool isHovered: hovered || externalHover

    implicitWidth: 32
    implicitHeight: 32
    focusPolicy: Qt.NoFocus
    hoverEnabled: true

    background: Item {}

    contentItem: Item {
        Icon {
            anchors.centerIn: parent
            iconName: root.iconName
            size: root.iconSize
            color: root.isHovered ? (root.closeButton ? Theme.danger : Theme.text) : Theme.text2
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }
}
