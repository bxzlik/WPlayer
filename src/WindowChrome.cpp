#include "WindowChrome.h"

#include <QCoreApplication>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>

namespace {

HWND toHwnd(void* hwnd)
{
    return static_cast<HWND>(hwnd);
}

// Толщина рамки изменения размера в физических пикселях
int resizeBorderHeight(HWND hwnd)
{
    const UINT dpi = GetDpiForWindow(hwnd);
    return GetSystemMetricsForDpi(SM_CYFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

int resizeBorderWidth(HWND hwnd)
{
    const UINT dpi = GetDpiForWindow(hwnd);
    return GetSystemMetricsForDpi(SM_CXFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

bool isShown(const QQuickItem* item)
{
    return item && item->isVisible() && item->opacity() > 0.01;
}

bool containsScenePoint(const QQuickItem* item, const QPointF& scenePos)
{
    return item->contains(item->mapFromScene(scenePos));
}

// Есть ли под точкой контрол (кнопка, слайдер…) или MouseArea.
// acceptedMouseButtons() не подходит: его выставляет, например, Text (ради ссылок).
bool interactiveAt(const QQuickItem* parent, const QPointF& scenePos)
{
    const QList<QQuickItem*> children = parent->childItems();
    for (auto it = children.crbegin(); it != children.crend(); ++it) {
        const QQuickItem* child = *it;
        if (!isShown(child) || !child->isEnabled() || !containsScenePoint(child, scenePos))
            continue;
        if (child->inherits("QQuickControl") || child->inherits("QQuickMouseArea")
            || interactiveAt(child, scenePos))
            return true;
    }
    return false;
}

// Окно ровно во весь монитор DWM/драйвер выводят напрямую, в обход композиции,
// и при каждой потере фокуса (переход на другой монитор, другое окно) режим
// вывода переключается — картинка на секунду замирает. Если окно на 1 px
// больше монитора, прямой вывод невозможен и переключать нечего. Лишнюю
// строку выносим за край, у которого нет соседнего монитора, — её не видно.
void extendPastMonitor(WINDOWPOS* pos)
{
    RECT rect{pos->x, pos->y, pos->x + pos->cx, pos->y + pos->cy};
    HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info) || !EqualRect(&rect, &info.rcMonitor))
        return;

    const RECT& m = info.rcMonitor;
    const LONG cx = (m.left + m.right) / 2;
    const LONG cy = (m.top + m.bottom) / 2;
    const auto freeAt = [](LONG x, LONG y) { return MonitorFromPoint(POINT{x, y}, MONITOR_DEFAULTTONULL) == nullptr; };

    if (freeAt(cx, m.bottom)) {
        pos->cy += 1;                       // вниз
    } else if (freeAt(cx, m.top - 1)) {
        pos->y -= 1;                        // вверх
        pos->cy += 1;
    } else if (freeAt(m.right, cy)) {
        pos->cx += 1;                       // вправо
    } else if (freeAt(m.left - 1, cy)) {
        pos->x -= 1;                        // влево
        pos->cx += 1;
    } else {
        pos->cy += 1;                       // со всех сторон мониторы — пусть будет низ
    }
}

} // namespace

WindowChrome::WindowChrome(QObject* parent) : QObject(parent)
{
    QCoreApplication::instance()->installNativeEventFilter(this);
}

WindowChrome::~WindowChrome()
{
    QCoreApplication::instance()->removeNativeEventFilter(this);
}

void WindowChrome::setWindow(QQuickWindow* window)
{
    if (m_window == window)
        return;
    m_window = window;
    m_hwnd = nullptr;
    emit windowChanged();
    if (m_complete)
        attach();
}

void WindowChrome::setTitleBar(QQuickItem* item)
{
    if (m_titleBar == item)
        return;
    m_titleBar = item;
    emit titleBarChanged();
}

void WindowChrome::setMaximizeButton(QQuickItem* item)
{
    if (m_maximizeButton == item)
        return;
    m_maximizeButton = item;
    emit maximizeButtonChanged();
}

void WindowChrome::componentComplete()
{
    m_complete = true;
    attach();
}

void WindowChrome::attach()
{
    if (!m_window)
        return;

    // Создаёт нативное окно, если его ещё нет: рамку нужно поменять до показа,
    // иначе на первом кадре мелькнёт системный заголовок.
    m_hwnd = reinterpret_cast<void*>(m_window->winId());
    const HWND hwnd = toHwnd(m_hwnd);

    // Тёмная рамка и системное меню
    const BOOL dark = TRUE;
    DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));


    QObject::disconnect(m_visibilityConnection);
    m_visibilityConnection = connect(m_window, &QWindow::visibilityChanged, this,
                                     &WindowChrome::updateFrameAttributes);
    updateFrameAttributes();

    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void WindowChrome::updateFrameAttributes()
{
    if (!m_hwnd || !m_window)
        return;
    const HWND hwnd = toHwnd(m_hwnd);
    const bool fullscreen = m_window->visibility() == QWindow::FullScreen;

    // Скругление Windows 11 — только у обычного окна (как в Bloom); в полном
    // экране DWM иначе скругляет углы монитора. Рамку DWM не рисуем никогда.
    const DWM_WINDOW_CORNER_PREFERENCE corners = fullscreen ? DWMWCP_DONOTROUND : DWMWCP_ROUND;
    DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corners, sizeof(corners));
    const COLORREF border = DWMWA_COLOR_NONE;
    DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, &border, sizeof(border));
}

void WindowChrome::setMaximizeState(bool hovered, bool pressed)
{
    if (m_maximizeHovered == hovered && m_maximizePressed == pressed)
        return;
    m_maximizeHovered = hovered;
    m_maximizePressed = pressed;
    emit maximizeStateChanged();
}

void WindowChrome::toggleMaximized()
{
    if (m_window->visibility() == QWindow::Maximized)
        m_window->showNormal();
    else
        m_window->showMaximized();
}

bool WindowChrome::nativeEventFilter(const QByteArray& eventType, void* message, qintptr* result)
{
    // Сообщения ввода (мышь, в том числе NC-клики) Qt пропускает через фильтр
    // только из цикла сообщений, до DispatchMessage, и тогда result == nullptr.
    // Отосланные сообщения (WM_NCCALCSIZE, WM_NCHITTEST) приходят из оконной
    // процедуры с настоящим result.
    if (!m_hwnd || !m_window || eventType != "windows_generic_MSG")
        return false;
    const auto setResult = [result](LRESULT value) {
        if (result)
            *result = value;
    };

    const MSG* msg = static_cast<const MSG*>(message);
    const HWND hwnd = toHwnd(m_hwnd);
    if (msg->hwnd != hwnd)
        return false;

    switch (msg->message) {
    case WM_NCACTIVATE:
        // При смене фокуса стандартная обработка перерисовывает системный
        // заголовок поверх окна — он на миг проступает. lParam = -1 оставляет
        // переключение активности, но без перерисовки неклиентской области.
        setResult(DefWindowProcW(hwnd, WM_NCACTIVATE, msg->wParam, -1));
        return true;

    case WM_WINDOWPOSCHANGING: {        // Только в полном экране: у обычного окна есть WS_CAPTION
        auto* pos = reinterpret_cast<WINDOWPOS*>(msg->lParam);
        if (!(GetWindowLongW(hwnd, GWL_STYLE) & WS_CAPTION) && !(pos->flags & SWP_NOSIZE))
            extendPastMonitor(pos);
        return false;  // дальше — обычная обработка Qt с исправленным размером
    }

    case WM_NCCALCSIZE: {        if (!msg->wParam)
            return false;
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(msg->lParam);
        if (!(GetWindowLongW(hwnd, GWL_STYLE) & WS_CAPTION)) {
            // Полный экран (WS_POPUP): клиентская область — всё окно
            setResult(0);
            return true;
        }
        if (IsZoomed(hwnd)) {
            // Развёрнутое окно выходит за края экрана на толщину рамки
            const int fx = resizeBorderWidth(hwnd);
            const int fy = resizeBorderHeight(hwnd);
            params->rgrc[0].left += fx;
            params->rgrc[0].right -= fx;
            params->rgrc[0].top += fy;
            params->rgrc[0].bottom -= fy;
        }
        // Обычное окно — без неклиентской области вовсе, как у Bloom
        // ("decorations": false, "shadow": false): нет ни системной рамки,
        // ни тени DWM. Размер меняется за края внутри окна (см. WM_NCHITTEST).
        setResult(0);
        return true;
    }

    case WM_NCHITTEST: {
        if (m_window->visibility() == QWindow::FullScreen)
            return false;

        POINT pt{GET_X_LPARAM(msg->lParam), GET_Y_LPARAM(msg->lParam)};
        ScreenToClient(hwnd, &pt);

        if (!IsZoomed(hwnd)) {
            RECT client;
            GetClientRect(hwnd, &client);
            // Сверху полоса тоньше, чтобы не отнимать кнопки окна у угла
            const int bx = resizeBorderWidth(hwnd);
            const int by = resizeBorderHeight(hwnd);
            const int topBand = by / 2;
            const bool left = pt.x < bx;
            const bool right = pt.x >= client.right - bx;
            const bool top = pt.y < topBand;
            const bool bottom = pt.y >= client.bottom - by;
            LRESULT edge = HTNOWHERE;
            if (top && left) edge = HTTOPLEFT;
            else if (top && right) edge = HTTOPRIGHT;
            else if (bottom && left) edge = HTBOTTOMLEFT;
            else if (bottom && right) edge = HTBOTTOMRIGHT;
            else if (left) edge = HTLEFT;
            else if (right) edge = HTRIGHT;
            else if (top) edge = HTTOP;
            else if (bottom) edge = HTBOTTOM;
            if (edge != HTNOWHERE) {
                setResult(edge);
                return true;
            }
        }
        const QPointF scenePos = QPointF(pt.x, pt.y) / m_window->devicePixelRatio();

        if (isShown(m_maximizeButton) && containsScenePoint(m_maximizeButton, scenePos)) {
            setResult(HTMAXBUTTON);  // Windows 11 покажет Snap Layouts
            return true;
        }
        if (isShown(m_titleBar) && containsScenePoint(m_titleBar, scenePos)
            && !interactiveAt(m_titleBar, scenePos)) {
            setResult(HTCAPTION);  // перетаскивание, двойной клик, системное меню
            return true;
        }
        return false;
    }

    case WM_NCMOUSEMOVE: {
        const bool overMaximize = msg->wParam == HTMAXBUTTON;
        setMaximizeState(overMaximize, overMaximize && m_maximizePressed);
        TRACKMOUSEEVENT track{sizeof(TRACKMOUSEEVENT), TME_LEAVE | TME_NONCLIENT, hwnd, 0};
        TrackMouseEvent(&track);
        emit nonClientMouseMoved();
        return false;
    }

    case WM_NCMOUSELEAVE:
    case WM_MOUSEMOVE:
        if (m_maximizeHovered || m_maximizePressed)
            setMaximizeState(false, false);
        return false;

    // Клики по «развернуть» обрабатываем сами: стандартная обработка
    // нарисовала бы поверх старую системную кнопку.
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
        if (msg->wParam != HTMAXBUTTON)
            return false;
        setMaximizeState(true, true);
        setResult(0);
        return true;

    case WM_NCLBUTTONUP:
        if (msg->wParam != HTMAXBUTTON)
            return false;
        if (m_maximizePressed)
            toggleMaximized();
        setMaximizeState(true, false);
        setResult(0);
        return true;

    default:
        return false;
    }
}
