pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// Меню правой кнопки в поле ввода (как .ctx в Bloom: плоские пункты без
// подложки, отклик — только осветлением). «Вырезать» и «Копировать» — когда
// есть выделение, «Вставить» — когда в буфере есть текст.
Popup {
    id: root

    property Item field: null  // поле с cut() / copy() / paste()
    property var model: []
    // Точка нажатия; положение — привязкой, высота известна только после раскладки
    property point anchor: Qt.point(0, 0)

    parent: Overlay.overlay
    padding: 5
    width: 180
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    x: Math.round(Math.max(8, Math.min(anchor.x, parent.width - width - 8)))
    y: Math.round(anchor.y + height > parent.height - 8 ? Math.max(8, anchor.y - height) : anchor.y)

    function openAt(target, pos) {
        const items = []
        if (target.selectedText !== "") {
            items.push({ action: "cut", label: "Вырезать", icon: "cut" })
            items.push({ action: "copy", label: "Копировать", icon: "copy" })
        }
        if (target.canPaste)
            items.push({ action: "paste", label: "Вставить", icon: "paste" })
        if (items.length === 0)
            return
        field = target
        model = items
        anchor = target.mapToItem(parent, pos.x, pos.y)
        open()
    }

    function run(action) {
        if (action === "cut") field.cut()
        else if (action === "copy") field.copy()
        else if (action === "paste") field.paste()
        close()
    }

    background: Rectangle {
        color: Theme.surface
        radius: Theme.radius * 0.9
        border.color: Theme.line
    }

    contentItem: Column {
        Repeater {
            model: root.model

            delegate: AbstractButton {
                id: item
                required property var modelData

                width: root.availableWidth
                height: 28
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                onClicked: root.run(item.modelData.action)

                readonly property color ink: item.hovered ? Theme.text : Qt.rgba(1, 1, 1, 0.78)

                contentItem: Row {
                    leftPadding: 10
                    spacing: 10

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 15
                        iconName: item.modelData.icon
                        color: item.ink
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: item.modelData.label
                        color: item.ink
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                }
                background: null
            }
        }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 180; easing.type: Easing.OutBack }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 }
    }
}
