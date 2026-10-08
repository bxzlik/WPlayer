#pragma once

#include <QAbstractNativeEventFilter>
#include <QObject>
#include <QPointer>
#include <QQmlParserStatus>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtQml/qqmlregistration.h>

// Убирает системную полосу заголовка Windows, но оставляет окно нативным:
// тень, скругления Windows 11, изменение размера за края, Aero Snap и
// Snap Layouts (наведение на «развернуть»). Сам заголовок рисуется в QML.
//
// titleBar — область, за которую окно перетаскивается (кнопки и прочие
// интерактивные элементы внутри неё продолжают работать как обычно).
// maximizeButton — кнопка «развернуть»: для неё Windows показывает Snap Layouts,
// поэтому её наведение/нажатие приходит сюда, а не в QML.
class WindowChrome : public QObject, public QQmlParserStatus, public QAbstractNativeEventFilter
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_ELEMENT

    Q_PROPERTY(QQuickWindow* window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(QQuickItem* titleBar READ titleBar WRITE setTitleBar NOTIFY titleBarChanged)
    Q_PROPERTY(QQuickItem* maximizeButton READ maximizeButton WRITE setMaximizeButton NOTIFY maximizeButtonChanged)
    Q_PROPERTY(bool maximizeHovered READ maximizeHovered NOTIFY maximizeStateChanged)
    Q_PROPERTY(bool maximizePressed READ maximizePressed NOTIFY maximizeStateChanged)

public:
    explicit WindowChrome(QObject* parent = nullptr);
    ~WindowChrome() override;

    QQuickWindow* window() const { return m_window; }
    void setWindow(QQuickWindow* window);
    QQuickItem* titleBar() const { return m_titleBar; }
    void setTitleBar(QQuickItem* item);
    QQuickItem* maximizeButton() const { return m_maximizeButton; }
    void setMaximizeButton(QQuickItem* item);
    bool maximizeHovered() const { return m_maximizeHovered; }
    bool maximizePressed() const { return m_maximizePressed; }

    void classBegin() override {}
    void componentComplete() override;

    bool nativeEventFilter(const QByteArray& eventType, void* message, qintptr* result) override;

signals:
    void windowChanged();
    void titleBarChanged();
    void maximizeButtonChanged();
    void maximizeStateChanged();
    // Курсор движется над областью заголовка (там QML не получает событий мыши)
    void nonClientMouseMoved();

private:
    void attach();
    void updateFrameAttributes();
    void setMaximizeState(bool hovered, bool pressed);
    void toggleMaximized();

    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_titleBar;
    QPointer<QQuickItem> m_maximizeButton;
    void* m_hwnd = nullptr;
    QMetaObject::Connection m_visibilityConnection;
    bool m_complete = false;
    bool m_maximizeHovered = false;
    bool m_maximizePressed = false;
};
