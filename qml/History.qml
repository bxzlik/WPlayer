import QtQuick
import QtCore

// История просмотра: последние источники (файл, ссылка или пара
// «видео + аудио») и позиция, на которой остановились. Новые — сверху.
// Хранится в настройках JSON-строкой.
QtObject {
    id: root

    // [{ video, audio, title, position, duration, watchedAt }]
    property var entries: []
    readonly property int limit: 100
    // Позиции меняются постоянно — на диск их пишет save() по таймеру
    property bool dirty: false

    property Settings store: Settings {
        category: "history"
    }

    Component.onCompleted: {
        try {
            const parsed = JSON.parse(store.value("json", "[]"))
            entries = Array.isArray(parsed) ? parsed : []
        } catch (e) {
            entries = []
        }
    }

    function indexOf(video, audio) {
        const a = audio || ""
        for (let i = 0; i < entries.length; ++i)
            if (entries[i].video === video && (entries[i].audio || "") === a) return i
        return -1
    }

    function find(video, audio) {
        const i = indexOf(video, audio)
        return i < 0 ? null : entries[i]
    }

    // Досмотрено: последние 5% или меньше 20 секунд до конца (титры)
    function finished(entry) {
        return entry.duration > 0
               && (entry.position >= entry.duration * 0.95 || entry.duration - entry.position < 20)
    }

    // С какой секунды продолжить: 0 — с начала
    function resumePosition(entry) {
        if (!entry || !(entry.duration > 0) || finished(entry) || entry.position < 10) return 0
        return entry.position
    }

    // Файл открылся — запись наверх
    function touch(video, audio, title, duration) {
        const i = indexOf(video, audio)
        const entry = i >= 0 ? entries[i] : { video: video, audio: audio || "", position: 0 }
        if (title !== "") entry.title = title
        if (duration > 0) entry.duration = duration
        entry.watchedAt = Date.now()
        const next = entries.slice()
        if (i >= 0) next.splice(i, 1)
        next.unshift(entry)
        if (next.length > limit) next.length = limit
        entries = next
        save()
    }

    // По ходу просмотра: без пересортировки и без записи на диск
    function update(video, audio, position, duration, title) {
        const entry = find(video, audio)
        if (!entry) return
        entry.position = position
        if (duration > 0) entry.duration = duration
        if (title !== "") entry.title = title
        entry.watchedAt = Date.now()
        dirty = true
    }

    function remove(video, audio) {
        const i = indexOf(video, audio)
        if (i < 0) return
        const next = entries.slice()
        next.splice(i, 1)
        entries = next
        save()
    }

    function clear() {
        entries = []
        save()
    }

    function save() {
        store.setValue("json", JSON.stringify(entries))
        if (dirty) {
            dirty = false
            entries = entries.slice()  // обновить списки (позиции)
        }
    }
}
