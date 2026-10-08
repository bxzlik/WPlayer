#include "MpvRenderThread.h"

#include <QOffscreenSurface>
#include <QOpenGLExtraFunctions>
#include <QOpenGLFramebufferObject>
#include <QtDebug>

#include <mpv/render_gl.h>

namespace {

void* getProcAddress(void*, const char* name)
{
    QOpenGLContext* ctx = QOpenGLContext::currentContext();
    return ctx ? reinterpret_cast<void*>(ctx->getProcAddress(QByteArray(name))) : nullptr;
}

} // namespace

MpvRenderThread::MpvRenderThread(std::shared_ptr<mpv_handle> mpv, QOpenGLContext* context,
                                 QOffscreenSurface* surface, std::function<void()> contextReady,
                                 std::function<void()> frameReady)
    : m_mpv(std::move(mpv)), m_context(context), m_surface(surface), m_contextReady(std::move(contextReady)),
      m_frameReady(std::move(frameReady))
{
    setObjectName(QStringLiteral("mpv render"));
}

MpvRenderThread::~MpvRenderThread()
{
    stop();
    wait();
}

void MpvRenderThread::setTargetSize(const QSize& size)
{
    QMutexLocker lock(&m_mutex);
    if (size == m_targetSize)
        return;
    m_targetSize = size;
    m_force = true;
    m_wake.wakeOne();
}

void MpvRenderThread::requestRender()
{
    QMutexLocker lock(&m_mutex);
    m_pending = true;
    m_wake.wakeOne();
}

void MpvRenderThread::stop()
{
    QMutexLocker lock(&m_mutex);
    m_quit = true;
    m_wake.wakeOne();
}

bool MpvRenderThread::takeFrame(Frame* frame)
{
    QMutexLocker lock(&m_mutex);
    if (m_ready < 0)
        return false;
    m_displayed = m_ready;
    m_ready = -1;
    frame->texture = m_buffers[m_displayed]->texture();
    frame->size = m_buffers[m_displayed]->size();
    frame->fence = m_fences[m_displayed];
    m_fences[m_displayed] = nullptr;
    return true;
}

int MpvRenderThread::freeBuffer() const
{
    for (int i = 0; i < int(m_buffers.size()); ++i) {
        if (i != m_ready && i != m_displayed)
            return i;
    }
    return 0;  // недостижимо: занято не больше двух буферов
}

void MpvRenderThread::publish(int index, GLsync fence)
{
    QMutexLocker lock(&m_mutex);
    if (m_ready >= 0 && m_fences[m_ready]) {
        // Предыдущий готовый кадр Qt так и не забрал — он больше не нужен
        m_context->extraFunctions()->glDeleteSync(m_fences[m_ready]);
        m_fences[m_ready] = nullptr;
    }
    m_ready = index;
    m_fences[index] = fence;
}

void MpvRenderThread::run()
{
    if (!m_context->makeCurrent(m_surface)) {
        qCritical("mpv: не удалось сделать OpenGL-контекст текущим");
        delete m_context;
        m_context = nullptr;
        return;
    }
    QOpenGLExtraFunctions* gl = m_context->extraFunctions();

    mpv_opengl_init_params glParams{};
    glParams.get_proc_address = &getProcAddress;
    mpv_render_param createParams[] = {
        {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glParams},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    if (mpv_render_context_create(&m_render, m_mpv.get(), createParams) < 0) {
        qCritical("mpv: не удалось создать OpenGL render context");
        m_context->doneCurrent();
        delete m_context;
        m_context = nullptr;
        return;
    }
    mpv_render_context_set_update_callback(
        m_render, [](void* self) { static_cast<MpvRenderThread*>(self)->requestRender(); }, this);
    m_contextReady();

    for (;;) {
        bool force = false;
        QSize size;
        {
            QMutexLocker lock(&m_mutex);
            while (!m_pending && !m_force && !m_quit)
                m_wake.wait(&m_mutex);
            if (m_quit)
                break;
            force = m_force;
            m_force = false;
            m_pending = false;
            size = m_targetSize;
        }

        const uint64_t flags = mpv_render_context_update(m_render);
        if (!(flags & MPV_RENDER_UPDATE_FRAME) && !force)
            continue;
        if (size.isEmpty())
            continue;

        int index;
        {
            QMutexLocker lock(&m_mutex);
            index = freeBuffer();
        }
        QOpenGLFramebufferObject*& fbo = m_buffers[index];
        if (!fbo || fbo->size() != size) {
            delete fbo;
            fbo = new QOpenGLFramebufferObject(size);
        }

        mpv_opengl_fbo mpvFbo{};
        mpvFbo.fbo = static_cast<int>(fbo->handle());
        mpvFbo.w = size.width();
        mpvFbo.h = size.height();
        // Обычная отрисовка OpenGL (начало снизу): Qt Quick с OpenGL-бэкендом
        // сам переворачивает нативную GL-текстуру при выводе. Проверено на
        // картинке с надписью сверху — с flipY = 1 кадр выходит вверх ногами.
        int flipY = 0;
        // Поток свой, поэтому mpv может спокойно ждать момента показа кадра
        // (BLOCK_FOR_TARGET_TIME по умолчанию) — интерфейс от этого не стоит.
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpvFbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(m_render, params);

        GLsync fence = gl->glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
        gl->glFlush();
        publish(index, fence);
        m_frameReady();
    }

    mpv_render_context_set_update_callback(m_render, nullptr, nullptr);
    mpv_render_context_free(m_render);
    m_render = nullptr;
    for (GLsync& fence : m_fences) {
        if (fence)
            gl->glDeleteSync(fence);
        fence = nullptr;
    }
    for (QOpenGLFramebufferObject*& fbo : m_buffers) {
        delete fbo;
        fbo = nullptr;
    }
    m_context->doneCurrent();
    delete m_context;
    m_context = nullptr;
}
