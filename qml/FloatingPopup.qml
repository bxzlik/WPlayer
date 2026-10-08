import QtQuick
import QtQuick.Controls

// Всплывающая панель над кнопкой (как #speedPicker в Bloom: поверхность
// блока, без рамки, скругление чуть меньше общего)
Popup {
    id: root

    parent: Overlay.overlay
    padding: 8
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Кнопка, от которой открыт попап, и когда он закрылся в последний раз
    property Item anchorItem: null
    property double closedAt: 0
    // aboutToHide, а не closed: closed приходит уже после анимации закрытия,
    // позже clicked того же нажатия
    onAboutToHide: closedAt = Date.now()

    // Повторное нажатие на ту же кнопку закрывает попап. Нажатие на кнопку
    // уже закрывает его как «клик снаружи», и сразу следом приходит clicked —
    // его и пропускаем, иначе попап тут же открылся бы снова.
    function toggleAbove(item) {
        if (opened) {
            close()
            return
        }
        if (anchorItem === item && Date.now() - closedAt < 300)
            return
        anchorItem = item
        openAbove(item)
    }

    // Положение считается привязкой от точки кнопки, а не один раз при
    // открытии: окончательная высота попапа известна только после раскладки
    // содержимого, и с ранней оценкой он наезжал на саму кнопку.
    property bool placeAbove: true
    property point anchorTop: Qt.point(0, 0)      // верх кнопки (центр — для «над»)
    property point anchorBottom: Qt.point(0, 0)   // низ кнопки (левый край — для «под»)

    x: Math.round(Math.max(8, Math.min(placeAbove ? anchorTop.x - width / 2 : anchorBottom.x,
                                       parent.width - width - 8)))
    y: {
        if (placeAbove)
            return Math.round(Math.max(8, anchorTop.y - height - 12))
        const below = anchorBottom.y + 6
        return Math.round(below + height > parent.height - 8 ? anchorTop.y - height - 6 : below)
    }

    function openAbove(item) {
        placeAbove = true
        anchorTop = item.mapToItem(parent, item.width / 2, 0)
        open()
    }

    function openBelow(item) {
        placeAbove = false
        anchorTop = item.mapToItem(parent, 0, 0)
        anchorBottom = item.mapToItem(parent, 0, item.height)
        open()
    }

    background: Rectangle {
        color: Theme.surface
        radius: Theme.radius * 0.95
        border.color: Theme.line
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 160; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 110 }
        NumberAnimation { property: "scale"; from: 1; to: 0.97; duration: 110 }
    }
}
