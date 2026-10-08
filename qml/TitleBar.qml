import QtQuick

// Заголовок окна в стиле Bloom (#winTitlebar): значок и название слева,
// голые кнопки 32×32 справа. Перетаскивание, двойной клик и Snap Layouts
// обрабатывает Windows через WindowChrome.
Item {
    id: root

    required property var window
    required property WindowChrome chrome
    property string title: ""
    property bool showSettings: false
    // Затемнение под заголовком (во время просмотра, поверх видео)
    property bool shaded: false

    signal settingsClicked()

    readonly property bool maximized: window.visibility === Window.Maximized
    readonly property bool fullscreen: window.visibility === Window.FullScreen
    readonly property bool hovered: hover.hovered
    readonly property alias maximizeButton: maximizeButton

    implicitHeight: 32

    HoverHandler { id: hover }

    Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: -56
        visible: root.shaded
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.7) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: buttons.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // Значок приложения — белая «W», как .win-icon (цвет --text2)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "W"
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.Bold
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 24
            text: root.title
            color: Theme.text2
            opacity: root.window.active ? 1 : 0.6
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Theme.bold
            elide: Text.ElideRight
        }
    }

    Row {
        id: buttons
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.rightMargin: 4

        CaptionButton {
            visible: root.showSettings
            iconName: "settings"
            iconSize: 16
            onClicked: root.settingsClicked()
        }
        CaptionButton {
            visible: !root.fullscreen
            iconName: "win-min"
            onClicked: root.window.showMinimized()
        }
        CaptionButton {
            id: maximizeButton
            visible: !root.fullscreen
            iconName: root.maximized ? "win-restore" : "win-max"
            iconSize: 12
            externalHover: root.chrome.maximizeHovered
            externalPress: root.chrome.maximizePressed
            // Обычно клик сюда не доходит (его перехватывает WindowChrome),
            // это запасной путь
            onClicked: root.maximized ? root.window.showNormal() : root.window.showMaximized()
        }
        CaptionButton {
            visible: !root.fullscreen
            iconName: "close"
            closeButton: true
            onClicked: root.window.close()
        }
    }
}
