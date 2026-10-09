pragma Singleton
import QtQuick

// Токены оформления — по образцу Bloom (тема Dark): плоская тёмная поверхность,
// полупрозрачная белая «плёнка» для рамок и заливок, один акцент.
QtObject {
    id: theme

    // --- Поверхности ---
    readonly property color bg: "#0a0a0a"
    // Модалки и шторки: цвет блока, чуть приподнятый к тексту (--ov-lift)
    readonly property color surface: "#0f0f0f"
    // Поверх видео — та же поверхность, но полупрозрачная
    readonly property color panel: Qt.rgba(0.04, 0.04, 0.04, 0.82)
    readonly property color border: "#282828"

    // Плёнка: рамки (--ovl-line / --ovl-line2), заливки, ховеры
    readonly property color line: Qt.rgba(1, 1, 1, 0.06)
    readonly property color line2: Qt.rgba(1, 1, 1, 0.13)
    function film(alpha) { return Qt.rgba(1, 1, 1, alpha) }

    // --- Текст ---
    readonly property color text: "#ffffff"
    readonly property color text2: "#9d9d9d"
    readonly property color muted: "#585858"
    readonly property color iconFg: "#d0d0d0"
    readonly property color danger: "#e5484d"

    // --- Акцент (меняется в настройках) ---
    property color accent: "#ffffff"
    // Контрастный цвет для текста на акценте
    readonly property color accentText: luminance(accent) > 0.55 ? "#000000" : "#ffffff"
    // Наведение на залитое акцентом: подмешиваем контрастный цвет
    readonly property color accentHover: Qt.tint(accent, Qt.rgba(accentText.r, accentText.g, accentText.b, 0.12))
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.16)
    readonly property color accentLine: Qt.rgba(accent.r, accent.g, accent.b, 0.40)

    readonly property var accentPresets: [
        "#ffffff", "#4d9fff", "#88c0d0", "#7bd88f", "#ffd24a",
        "#d4875a", "#ff5c8a", "#ff4d4f", "#b48cff", "#2dd4bf"
    ]

    function luminance(c) {
        function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
    }

    // --- Геометрия и шрифт ---
    readonly property int radius: 14
    readonly property real radiusSm: 8.4      // кнопки и поля (--radius × 0.6)
    readonly property string font: "Inter"
    readonly property int bold: Font.Medium   // одна «жирная» ступень, как в Bloom

    // Кривая выезда модалок и шторок (cubic-bezier(.22,1,.36,1))
    readonly property var slideCurve: [0.22, 1, 0.36, 1, 1, 1]
    readonly property int slideDuration: 420

    // --- Anime4K ---
    readonly property var anime4kModes: [
        { value: "off", label: "Выкл",     name: "Выключено", detail: "Без апскейла" },
        { value: "A",   label: "A",        name: "Mode A",   detail: "1080p: восстановление линий + апскейл" },
        { value: "B",   label: "B",        name: "Mode B",   detail: "720p: мягкое восстановление + апскейл" },
        { value: "C",   label: "C",        name: "Mode C",   detail: "480p и ниже: апскейл с шумоподавлением" },
        { value: "AA",  label: "A+A",      name: "Mode A+A", detail: "Сильнее A, тяжелее для видеокарты" },
        { value: "BB",  label: "B+B",      name: "Mode B+B", detail: "Сильнее B, тяжелее для видеокарты" },
        { value: "CA",  label: "C+A",      name: "Mode C+A", detail: "Сильнее C, тяжелее для видеокарты" }
    ]

    function anime4kMode(value) {
        for (let i = 0; i < anime4kModes.length; ++i)
            if (anime4kModes[i].value === value) return anime4kModes[i]
        return anime4kModes[0]
    }

    // --- Скорость ---
    readonly property var speeds: [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    readonly property real holdSpeed: 2

    function formatSpeed(speed) {
        return (Math.round(speed * 100) / 100) + "×"
    }

    // Соседняя ступень из speeds (direction ±1); со скорости между
    // ступенями — к ближайшей в эту сторону
    function stepSpeed(speed, direction) {
        if (direction > 0) {
            for (let i = 0; i < speeds.length; ++i)
                if (speeds[i] > speed + 0.001) return speeds[i]
            return speeds[speeds.length - 1]
        }
        for (let j = speeds.length - 1; j >= 0; --j)
            if (speeds[j] < speed - 0.001) return speeds[j]
        return speeds[0]
    }

    function volumeIcon(volume, muted) {
        if (muted || volume <= 0) return "muted"
        return volume < 50 ? "volume-low" : "volume"
    }

    // --- Форматирование ---
    function pad2(n) { return n < 10 ? "0" + n : "" + n }

    function formatTime(seconds) {
        let s = (isFinite(seconds) && seconds > 0) ? Math.floor(seconds) : 0
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        s = s % 60
        return h > 0 ? h + ":" + pad2(m) + ":" + pad2(s) : m + ":" + pad2(s)
    }

    function formatDelay(seconds) {
        const ms = Math.round(seconds * 1000)
        return (ms > 0 ? "+" : ms < 0 ? "−" : "") + Math.abs(ms) + " мс"
    }
}
