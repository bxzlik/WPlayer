pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtCore

ApplicationWindow {
    id: win

    width: 1280
    height: 760
    minimumWidth: 720
    minimumHeight: 420
    visible: true
    color: Theme.bg
    title: mpv.idle || mpv.mediaTitle === "" ? "WPlayer" : mpv.mediaTitle + " — WPlayer"
    font.family: Theme.font

    Material.theme: Material.Dark
    Material.accent: Theme.accent
    Material.background: Theme.surface

    // Файл из командной строки (передаётся из main.cpp)
    property string startupFile: ""

    property bool controlsVisible: true
    property int restoreVisibility: Window.Windowed
    readonly property bool isFullscreen: visibility === Window.FullScreen

    // Пока true — интерфейс не прячется
    readonly property bool uiPinned: mpv.idle || mpv.paused || controls.busy || topBar.hovered
                                     || urlDialog.visible || settingsPanel.visible || infoPanel.visible
                                     || historyPanel.visible

    // Что сделать, когда yt-dlp вернёт прямую ссылку на аудио: "pair" | "add"
    property string pendingAudioAction: ""
    property string pendingVideo: ""
    property string pendingAudioSource: ""  // страница, с которой yt-dlp берёт звук
    property var pendingSubtitles: []

    // История: что открывается сейчас и что уже открыто ({ video, audio }).
    // Пока nowPlaying пуст, позиция в историю не пишется.
    property var loadingEntry: null
    property var nowPlaying: null
    property real resumedFrom: 0

    readonly property var audioExtensions: ["mka", "m4a", "aac", "mp3", "opus", "ogg", "oga", "flac", "wav", "ac3", "eac3", "dts", "thd"]
    readonly property var subtitleExtensions: ["ass", "ssa", "srt", "vtt", "sub", "sup"]

    Settings {
        id: settings
        category: "player"
        property real volume: 80
        property string anime4kMode: "off"
        property bool anime4kFast: false
        property bool hwdec: true
        property string alang: ""
        property string slang: "rus,ru,eng,en"
        property string lastVideoUrl: ""
        property string lastAudioUrl: ""
        property string accent: "#ffffff"
        property bool resume: true
    }

    History {
        id: watchHistory
    }

    // Позиции пишутся на диск раз в несколько секунд и при закрытии
    Timer {
        interval: 5000
        repeat: true
        running: watchHistory.dirty
        onTriggered: watchHistory.save()
    }
    onClosing: watchHistory.save()

    // Акцент из настроек — во всю тему
    Binding {
        target: Theme
        property: "accent"
        value: settings.accent
    }

    // ------------------------------------------------------------------
    // Логика
    // ------------------------------------------------------------------

    // До init() не сохраняем значения из mpv, иначе громкость по умолчанию
    // затрёт сохранённую
    property bool ready: false

    function init() {
        mpv.volume = settings.volume
        mpv.hwdec = settings.hwdec
        mpv.anime4kFast = settings.anime4kFast
        if (settings.alang !== "") mpv.setMpvProperty("alang", settings.alang)
        if (settings.slang !== "") mpv.setMpvProperty("slang", settings.slang)
        if (settings.anime4kMode !== "off") mpv.setShaderPreset(settings.anime4kMode)
        if (startupFile !== "") playMedia(startupFile)
        ready = true
    }

    Component.onCompleted: Qt.callLater(init)

    function poke() {
        controlsVisible = true
        hideTimer.restart()
    }

    onUiPinnedChanged: {
        if (uiPinned) controlsVisible = true
        else hideTimer.restart()
    }

    function toggleFullscreen() {
        if (isFullscreen) {
            if (restoreVisibility === Window.Maximized) showMaximized()
            else showNormal()
        } else {
            restoreVisibility = visibility === Window.Maximized ? Window.Maximized : Window.Windowed
            showFullScreen()
        }
    }

    function extensionOf(url) {
        const s = url.toString().split(/[?#]/)[0]
        const dot = s.lastIndexOf(".")
        return dot < 0 ? "" : s.substring(dot + 1).toLowerCase()
    }

    function changeVolume(delta) {
        mpv.volume = Math.max(0, Math.min(100, Math.round(mpv.volume + delta)))
        if (mpv.muted) mpv.muted = false
        toast.show("Громкость " + Math.round(mpv.volume) + "%")
    }

    function changeAudioDelay(delta) {
        mpv.audioDelay = Math.round((mpv.audioDelay + delta) * 1000) / 1000
        toast.show("Задержка аудио " + Theme.formatDelay(mpv.audioDelay))
    }

    function setSpeed(speed) {
        mpv.speed = speed
        toast.show("Скорость " + Theme.formatSpeed(speed))
    }

    // Удержание кнопки мыши на кадре — ускорение до Theme.holdSpeed, пока держат
    // (как в anibloom). Пауза при этом не переключается.
    property real speedBeforeHold: 0   // 0 — удержания нет
    readonly property bool holding: speedBeforeHold > 0

    function startHold() {
        if (mpv.idle || holding) return
        speedBeforeHold = mpv.speed
        mpv.speed = Theme.holdSpeed
    }

    function endHold() {
        if (!holding) return
        mpv.speed = speedBeforeHold
        speedBeforeHold = 0
    }

    // Все открытия файлов идут сюда: запись в истории ищется по video + audio,
    // и если в прошлый раз не досмотрели — продолжаем с того места.
    // audioDirect — прямая ссылка на звук, полученная yt-dlp со страницы audio.
    function playMedia(video, audio, audioDirect) {
        const v = mpv.normalizedSource(video)
        const a = audio ? mpv.normalizedSource(audio) : ""
        if (v === "") return
        nowPlaying = null
        loadingEntry = { video: v, audio: a }
        resumedFrom = settings.resume ? watchHistory.resumePosition(watchHistory.find(v, a)) : 0
        if (a !== "") mpv.openWithAudio(v, audioDirect || a, resumedFrom)
        else mpv.open(v, resumedFrom)
    }

    // Запись из истории: пара со страницей сайта снова идёт через yt-dlp
    function openEntry(entry) {
        if (entry.audio) openPair(entry.video, entry.audio, true)
        else playMedia(entry.video)
    }

    function openSource(url) {
        settings.lastVideoUrl = url
        playMedia(url)
    }

    // Видео из одной ссылки, звук из другой
    function openPair(video, audio, fromHistory) {
        if (!fromHistory) {
            settings.lastVideoUrl = video
            settings.lastAudioUrl = audio
        }
        if (downloader.isDirectMedia(audio)) {
            playMedia(video, audio)
        } else {
            pendingAudioAction = "pair"
            pendingVideo = video
            pendingAudioSource = audio
            toast.show("Получаю аудиопоток через yt-dlp…")
            downloader.resolveAudio(audio)
        }
    }

    function addAudioSource(audio) {
        if (downloader.isDirectMedia(audio)) {
            mpv.addAudio(audio)
        } else {
            pendingAudioAction = "add"
            toast.show("Получаю аудиопоток через yt-dlp…")
            downloader.resolveAudio(audio)
        }
    }

    // Перетаскивание: видео открывается, аудио и субтитры добавляются дорожками
    function handleDrop(urls) {
        let video = ""
        const audios = []
        const subs = []
        for (let i = 0; i < urls.length; ++i) {
            const u = urls[i].toString()
            const ext = extensionOf(u)
            if (subtitleExtensions.indexOf(ext) >= 0) subs.push(u)
            else if (audioExtensions.indexOf(ext) >= 0) audios.push(u)
            else if (video === "") video = u
        }

        if (video !== "") {
            pendingSubtitles = subs
            playMedia(video, audios.length > 0 ? audios[0] : "")
            return
        }
        if (mpv.idle) {
            if (audios.length > 0) playMedia(audios[0])
            return
        }
        audios.forEach(a => mpv.addAudio(a))
        subs.forEach(s => mpv.addSubtitle(s))
    }

    // ------------------------------------------------------------------
    // Видео и взаимодействие с ним
    // ------------------------------------------------------------------

    MpvObject {
        id: mpv
        anchors.fill: parent

        onVolumeChanged: if (win.ready) settings.volume = volume
        onErrorOccurred: message => toast.show(message, true)
        onShaderPresetChanged: {
            settings.anime4kMode = shaderPreset
            // При запуске пресет восстанавливается из настроек — без тоста
            if (win.ready)
                toast.show("Anime4K: " + Theme.anime4kMode(shaderPreset).name)
        }
        onFileLoaded: {
            win.pendingSubtitles.forEach(s => mpv.addSubtitle(s))
            win.pendingSubtitles = []

            const entry = win.loadingEntry
            win.loadingEntry = null
            if (entry) {
                watchHistory.touch(entry.video, entry.audio, mpv.mediaTitle, mpv.duration)
                win.nowPlaying = entry
            }
            if (win.resumedFrom > 0) {
                toast.show("Продолжено с " + Theme.formatTime(win.resumedFrom) + "  ·  Home — с начала")
                win.resumedFrom = 0
            }
        }
        onLoadingChanged: if (loading) win.nowPlaying = null
        onPositionChanged: {
            if (win.nowPlaying && !loading)
                watchHistory.update(win.nowPlaying.video, win.nowPlaying.audio, position, duration, mediaTitle)
        }
    }

    YtDlp {
        id: downloader
        onAudioResolved: (source, direct) => {
            if (win.pendingAudioAction === "pair") win.playMedia(win.pendingVideo, win.pendingAudioSource, direct)
            else if (win.pendingAudioAction === "add") mpv.addAudio(direct)
            win.pendingAudioAction = ""
        }
        onResolveFailed: message => {
            win.pendingAudioAction = ""
            toast.show("yt-dlp: " + message, true)
        }
        onUpdateFinished: (ok, message) => toast.show(message !== "" ? message : (ok ? "yt-dlp обновлён" : "Ошибка обновления yt-dlp"), !ok)
    }

    MouseArea {
        id: frameMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: win.controlsVisible ? Qt.ArrowCursor : Qt.BlankCursor

        // Долгое нажатие — удержание 2×; его отпускание не клик.
        // Свой таймер, а не pressAndHold: тот не срабатывает, если за время
        // нажатия MouseArea потеряла hover.
        property bool held: false

        Timer {
            id: holdTimer
            interval: 350
            onTriggered: {
                frameMouse.held = true
                win.startHold()
            }
        }

        onPositionChanged: win.poke()
        onPressed: {
            held = false
            holdTimer.restart()
        }
        onReleased: {
            holdTimer.stop()
            win.endHold()
        }
        onCanceled: {
            holdTimer.stop()
            win.endHold()
        }
        // Пауза — сразу по первому клику, без ожидания возможного второго.
        // Если клик оказался двойным, второй возвращает паузу как была
        // и переключает полный экран (так же ведут себя mpv и MPC).
        onClicked: if (!held && !mpv.idle) mpv.togglePause()
        onDoubleClicked: {
            if (!mpv.idle) mpv.togglePause()
            win.toggleFullscreen()
        }
        onWheel: wheel => win.changeVolume(wheel.angleDelta.y > 0 ? 5 : -5)
    }

    Timer {
        id: hideTimer
        interval: 2500
        onTriggered: if (!win.uiPinned) win.controlsVisible = false
    }

    // ------------------------------------------------------------------
    // Стартовый экран
    // ------------------------------------------------------------------

    Item {
        anchors.fill: parent
        visible: mpv.idle && !mpv.loading && !downloader.resolving

        Column {
            anchors.centerIn: parent
            spacing: 14

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.StyledText
                text: "<font color='" + Theme.accent + "'>W</font>Player"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 52
                font.weight: Font.Bold
                font.letterSpacing: -1.5
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Перетащите файл в окно или выберите источник"
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 14
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                topPadding: 12

                PillButton {
                    primary: true
                    large: true
                    iconName: "folder"
                    text: "Открыть файл"
                    onClicked: fileDialog.openFor("video")
                }
                PillButton {
                    large: true
                    iconName: "link"
                    text: "Ссылка"
                    onClicked: urlDialog.openFor("single", settings.lastVideoUrl)
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 4
                text: "Ctrl+O  ·  Ctrl+L"
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 12
            }

            // Недавние: столько строк, сколько влезает по высоте окна
            Column {
                id: recent
                readonly property int rows: Math.max(0, Math.min(4, Math.floor((win.height - 330) / 58)))

                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(460, win.width - 48)
                topPadding: 22
                spacing: 2
                visible: rows > 0 && watchHistory.entries.length > 0

                Item {
                    width: parent.width
                    height: 26

                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Недавние"
                        color: Theme.text2
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Theme.bold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.7
                    }
                    AbstractButton {
                        id: allHistory
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        padding: 4
                        rightPadding: 10
                        hoverEnabled: true
                        focusPolicy: Qt.NoFocus
                        onClicked: historyPanel.open()
                        background: Item {}
                        contentItem: Text {
                            text: "Вся история  ·  Ctrl+H"
                            color: allHistory.hovered ? Theme.text : Theme.text2
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                    }
                }

                Repeater {
                    model: watchHistory.entries.slice(0, recent.rows)
                    delegate: HistoryRow {
                        required property var modelData
                        width: recent.width
                        entry: modelData
                        watched: watchHistory.finished(modelData)
                        onClicked: win.openEntry(modelData)
                        onRemoveClicked: watchHistory.remove(modelData.video, modelData.audio)
                    }
                }
            }
        }
    }
    BusyIndicator {
        anchors.centerIn: parent
        // При видимом управлении буферизацию показывает индикатор на месте паузы
        running: mpv.loading || downloader.resolving || (mpv.buffering && !controls.visible)
        visible: running
    }

    // ------------------------------------------------------------------
    // Оверлеи поверх видео
    // ------------------------------------------------------------------

    TitleBar {
        id: topBar
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        window: win
        chrome: windowChrome
        title: win.title
        showSettings: mpv.idle
        showInfo: !mpv.idle
        shaded: !mpv.idle
        opacity: win.controlsVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        onSettingsClicked: settingsPanel.open()
        onHistoryClicked: historyPanel.open()
        onInfoClicked: infoPanel.open()
    }

    WindowChrome {
        id: windowChrome
        window: win
        titleBar: topBar
        maximizeButton: topBar.maximizeButton
        onNonClientMouseMoved: win.poke()
    }

    ControlBar {
        id: controls
        anchors.fill: parent
        player: mpv
        fullscreen: win.isFullscreen
        opacity: win.controlsVisible && !mpv.idle ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        onToggleFullscreen: win.toggleFullscreen()
        onOpenSettings: settingsPanel.open()
        onAddAudioFile: fileDialog.openFor("audio")
        onAddAudioUrl: urlDialog.openFor("audio", "", settings.lastAudioUrl)
        onAddSubtitleFile: fileDialog.openFor("subtitle")
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            if (drop.hasUrls) {
                win.handleDrop(drop.urls)
                drop.acceptProposedAction()
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 16
            visible: dropArea.containsDrag
            radius: 20
            color: Theme.accentSoft
            border.color: Theme.accent
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "Отпустите, чтобы открыть"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 20
                font.weight: Theme.bold
            }
        }
    }

    // Плашка «2×», пока держат кнопку мыши
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 56
        width: holdRow.implicitWidth + 28
        height: 34
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: win.holding ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        Row {
            id: holdRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.formatSpeed(Theme.holdSpeed)
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Theme.bold
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "fast-forward"
                size: 16
                color: Theme.text
            }
        }
    }

    Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(72, parent.height * 0.12)
    }

    // ------------------------------------------------------------------
    // Диалоги
    // ------------------------------------------------------------------

    FileDialog {
        id: fileDialog
        property string purpose: "video"

        function openFor(newPurpose) {
            purpose = newPurpose
            open()
        }

        title: purpose === "audio" ? "Добавить аудиодорожку"
             : purpose === "subtitle" ? "Добавить субтитры"
             : "Открыть видео"
        nameFilters: purpose === "audio"
                     ? ["Аудио (*.mka *.m4a *.aac *.mp3 *.opus *.ogg *.flac *.wav *.ac3 *.eac3 *.dts)", "Все файлы (*)"]
                     : purpose === "subtitle"
                       ? ["Субтитры (*.ass *.ssa *.srt *.vtt *.sub *.sup)", "Все файлы (*)"]
                       : ["Видео (*.mkv *.mp4 *.avi *.webm *.mov *.m2ts *.ts *.flv *.wmv *.m4v)", "Все файлы (*)"]

        onAccepted: {
            const file = selectedFile.toString()
            if (purpose === "audio") mpv.addAudio(file)
            else if (purpose === "subtitle") mpv.addSubtitle(file)
            else win.playMedia(file)
        }
    }

    OpenUrlDialog {
        id: urlDialog
        blurSource: win.contentItem
        onOpenSingle: url => win.openSource(url)
        onOpenPair: (video, audio) => win.openPair(video, audio)
        onAddAudio: url => {
            settings.lastAudioUrl = url
            win.addAudioSource(url)
        }
    }

    SettingsPanel {
        id: settingsPanel
        fullscreen: win.isFullscreen
        player: mpv
        ytdlp: downloader
        prefs: settings
    }

    HistoryPanel {
        id: historyPanel
        fullscreen: win.isFullscreen
        history: watchHistory
        onEntryChosen: entry => win.openEntry(entry)
    }

    InfoPanel {
        id: infoPanel
        fullscreen: win.isFullscreen
        player: mpv
    }

    // ------------------------------------------------------------------
    // Горячие клавиши
    // ------------------------------------------------------------------

    readonly property bool keysEnabled: !urlDialog.visible

    Shortcut { sequences: ["Space", "K"]; enabled: win.keysEnabled; onActivated: mpv.togglePause() }
    Shortcut { sequence: "Left"; enabled: win.keysEnabled; onActivated: mpv.seekRelative(-5) }
    Shortcut { sequence: "Right"; enabled: win.keysEnabled; onActivated: mpv.seekRelative(5) }
    Shortcut { sequence: "Shift+Left"; enabled: win.keysEnabled; onActivated: mpv.seekRelative(-1) }
    Shortcut { sequence: "Shift+Right"; enabled: win.keysEnabled; onActivated: mpv.seekRelative(1) }
    Shortcut { sequence: "Ctrl+Right"; enabled: win.keysEnabled; onActivated: mpv.seekRelative(85) }
    Shortcut { sequence: "Ctrl+Left"; enabled: win.keysEnabled; onActivated: mpv.seekRelative(-85) }
    Shortcut { sequence: "Home"; enabled: win.keysEnabled && !mpv.idle; onActivated: mpv.seek(0) }
    Shortcut { sequence: "PgUp";enabled: win.keysEnabled; onActivated: mpv.seekChapter(-1) }
    Shortcut { sequence: "PgDown"; enabled: win.keysEnabled; onActivated: mpv.seekChapter(1) }
    // Клавиши-знаки в русской раскладке дают буквы: [ ] , . → Х Ъ Б Ю
    Shortcut { sequences: ["[", "Х"]; enabled: win.keysEnabled && !win.holding; onActivated: win.setSpeed(Theme.stepSpeed(mpv.speed, -1)) }
    Shortcut { sequences: ["]", "Ъ"]; enabled: win.keysEnabled && !win.holding; onActivated: win.setSpeed(Theme.stepSpeed(mpv.speed, 1)) }
    Shortcut { sequence: "Backspace"; enabled: win.keysEnabled && !win.holding; onActivated: win.setSpeed(1) }
    Shortcut { sequences: [",", "Б"]; enabled: win.keysEnabled; onActivated: mpv.command(["frame-back-step"]) }
    Shortcut { sequences: [".", "Ю"]; enabled: win.keysEnabled; onActivated: mpv.command(["frame-step"]) }
    Shortcut { sequence: "Up"; enabled: win.keysEnabled; onActivated: win.changeVolume(5) }
    Shortcut { sequence: "Down"; enabled: win.keysEnabled; onActivated: win.changeVolume(-5) }
    Shortcut {
        sequence: "M"
        enabled: win.keysEnabled
        onActivated: {
            mpv.muted = !mpv.muted
            toast.show(mpv.muted ? "Звук выключен" : "Звук включён")
        }
    }
    Shortcut { sequence: "F"; enabled: win.keysEnabled; onActivated: win.toggleFullscreen() }
    Shortcut { sequence: "Esc"; enabled: win.isFullscreen && win.keysEnabled; onActivated: win.toggleFullscreen() }
    Shortcut { sequence: "A"; enabled: win.keysEnabled; onActivated: mpv.command(["cycle", "aid"]) }
    Shortcut { sequence: "S"; enabled: win.keysEnabled; onActivated: mpv.command(["cycle", "sid"]) }
    Shortcut { sequence: "Ctrl+-"; enabled: win.keysEnabled; onActivated: win.changeAudioDelay(-0.05) }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; enabled: win.keysEnabled; onActivated: win.changeAudioDelay(0.05) }
    Shortcut { sequence: "Ctrl+0"; enabled: win.keysEnabled; onActivated: mpv.setShaderPreset("off") }
    Shortcut { sequence: "Ctrl+1"; enabled: win.keysEnabled; onActivated: mpv.setShaderPreset("A") }
    Shortcut { sequence: "Ctrl+2"; enabled: win.keysEnabled; onActivated: mpv.setShaderPreset("B") }
    Shortcut { sequence: "Ctrl+3"; enabled: win.keysEnabled; onActivated: mpv.setShaderPreset("C") }
    Shortcut { sequence: "Ctrl+4"; enabled: win.keysEnabled; onActivated: mpv.setShaderPreset("AA") }
    Shortcut { sequence: "Ctrl+5"; enabled: win.keysEnabled; onActivated: mpv.setShaderPreset("BB") }
    Shortcut { sequence: "Ctrl+6"; enabled: win.keysEnabled; onActivated: mpv.setShaderPreset("CA") }
    Shortcut { sequence: "Ctrl+O"; onActivated: fileDialog.openFor("video") }
    Shortcut { sequence: "Ctrl+L"; onActivated: urlDialog.openFor("single", settings.lastVideoUrl) }
    Shortcut { sequence: "Ctrl+Shift+L"; onActivated: urlDialog.openFor("pair", settings.lastVideoUrl, settings.lastAudioUrl) }
    Shortcut {
        sequence: "I"
        enabled: win.keysEnabled && !mpv.idle
        onActivated: infoPanel.visible ? infoPanel.close() : infoPanel.open()
    }
    Shortcut { sequence: "Ctrl+H"; onActivated: historyPanel.visible ? historyPanel.close() : historyPanel.open() }
    Shortcut { sequence: "Ctrl+,"; onActivated: settingsPanel.visible ? settingsPanel.close() : settingsPanel.open() }
}
