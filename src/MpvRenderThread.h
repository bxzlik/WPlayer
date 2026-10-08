#pragma once

#include <QMutex>
#include <QOpenGLContext>
#include <QSize>
#include <QThread>
#include <QWaitCondition>
#include <qopengl.h>

#include <array>
#include <functional>
#include <memory>

#include <mpv/client.h>

class QOffscreenSurface;
class QOpenGLFramebufferObject;
struct mpv_render_context;

// Отрисовка mpv в собственном потоке и OpenGL-контексте (общем с контекстом
// Qt Quick). Тяжёлые проходы (Anime4K) больше не задерживают кадры интерфейса:
// mpv рисует в один из трёх буферов, а Qt на каждом кадре забирает последний
// готовый. Готовность кадра на GPU передаётся через fence (glFenceSync).
class MpvRenderThread : public QThread
{
public:
    struct Frame
    {
        GLuint texture = 0;
        QSize size;
        GLsync fence = nullptr;  // переходит к получателю: дождаться и удалить
    };

    // context создан с shareContext = контекст Qt Quick и ещё не текущий;
    // поток забирает его себе и удаляет при завершении.
    // contextReady — render context mpv создан (до этого loadfile не откроет видео),
    // frameReady — готов новый кадр. Оба вызываются из потока отрисовки.
    MpvRenderThread(std::shared_ptr<mpv_handle> mpv, QOpenGLContext* context, QOffscreenSurface* surface,
                    std::function<void()> contextReady, std::function<void()> frameReady);
    ~MpvRenderThread() override;

    // Размер кадра в физических пикселях. При изменении кадр перерисовывается.
    void setTargetSize(const QSize& size);
    // Последний готовый кадр, если он новее отданного ранее (вызывать из
    // потока рендера Qt, пока GUI-поток стоит на синхронизации).
    bool takeFrame(Frame* frame);
    void stop();

protected:
    void run() override;

private:
    void requestRender();
    int freeBuffer() const;
    void publish(int index, GLsync fence);

    std::shared_ptr<mpv_handle> m_mpv;
    QOpenGLContext* m_context;
    QOffscreenSurface* m_surface;
    std::function<void()> m_contextReady;
    std::function<void()> m_frameReady;
    mpv_render_context* m_render = nullptr;

    QMutex m_mutex;
    QWaitCondition m_wake;
    bool m_pending = false;   // mpv просит перерисовку
    bool m_force = false;     // перерисовать даже без нового кадра (сменился размер)
    bool m_quit = false;
    QSize m_targetSize;

    // Буферы: один показывает Qt, один готов к показу, в третий рисует mpv
    std::array<QOpenGLFramebufferObject*, 3> m_buffers{};
    std::array<GLsync, 3> m_fences{};
    int m_ready = -1;
    int m_displayed = -1;
};
