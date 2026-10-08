import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Открытие по ссылке: одна ссылка, «видео + аудио» или только аудио
ModalDialog {
    id: root

    // "single" | "pair" | "audio"
    property string mode: "single"

    signal openSingle(string url)
    signal openPair(string videoUrl, string audioUrl)
    signal addAudio(string url)

    readonly property bool audioOnly: mode === "audio"
    readonly property bool withAudio: audioOnly || pairSwitch.checked
    readonly property bool valid: audioOnly ? audioField.text.trim() !== ""
                                            : videoField.text.trim() !== ""
                                              && (!pairSwitch.checked || audioField.text.trim() !== "")

    function openFor(newMode, videoText, audioText) {
        mode = newMode
        pairSwitch.checked = newMode === "pair"
        videoField.text = videoText || ""
        audioField.text = audioText || ""
        open()
    }

    function submit() {
        if (!valid)
            return
        const video = videoField.text.trim()
        const audio = audioField.text.trim()
        if (audioOnly) addAudio(audio)
        else if (withAudio) openPair(video, audio)
        else openSingle(video)
        close()
    }

    title: audioOnly ? "Аудио по ссылке" : "Открыть ссылку"
    subtitle: audioOnly ? "Дорожка добавится к текущему видео и сразу включится"
                        : "Файл, прямая ссылка или страница сайта — сайты открываются через yt-dlp"

    onOpened: (audioOnly ? audioField : videoField).forceActiveFocus()

    component FieldLabel: Text {
        color: Theme.text2
        font.family: Theme.font
        font.pixelSize: 12
        font.weight: Theme.bold
    }

    FieldLabel {
        visible: !root.audioOnly
        text: "Видео"
    }
    UiTextField {
        id: videoField
        visible: !root.audioOnly
        Layout.fillWidth: true
        placeholderText: "https://…"
        onAccepted: root.submit()
    }

    // Строка-переключатель (как ToggleRow в Bloom): кликается целиком
    AbstractButton {
        id: pairRow
        visible: !root.audioOnly
        Layout.fillWidth: true
        Layout.topMargin: 4
        leftPadding: 14
        rightPadding: 12
        topPadding: 10
        bottomPadding: 10
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        onClicked: pairSwitch.toggle()

        background: Rectangle {
            radius: Theme.radiusSm * 1.2
            color: Theme.film(pairRow.hovered ? 0.05 : 0.03)
            border.color: Theme.line
        }

        contentItem: RowLayout {
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "Аудио из другой ссылки"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Theme.bold
                }
                Text {
                    Layout.fillWidth: true
                    text: "Картинка из первой ссылки, звук — из второй"
                    color: Theme.text2
                    font.family: Theme.font
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
            UiSwitch {
                id: pairSwitch
            }
        }
    }

    FieldLabel {
        visible: root.withAudio
        Layout.topMargin: root.audioOnly ? 0 : 4
        text: "Аудио"
    }
    UiTextField {
        id: audioField
        visible: root.withAudio
        Layout.fillWidth: true
        placeholderText: "Ссылка с нужной озвучкой или путь к файлу"
        onAccepted: root.submit()
    }
    Text {
        visible: root.withAudio && !root.audioOnly
        Layout.fillWidth: true
        text: "Если звук спешит или отстаёт — подстройте его кнопкой синхронизации на панели"
        color: Theme.muted
        font.family: Theme.font
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    buttons: [
        PillButton {
            Layout.fillWidth: true
            large: true
            text: "Отмена"
            onClicked: root.close()
        },
        PillButton {
            Layout.fillWidth: true
            large: true
            primary: true
            enabled: root.valid
            text: root.audioOnly ? "Добавить" : "Открыть"
            onClicked: root.submit()
        }
    ]
}
