#include "MpvObject.h"

#include "Anime4K.h"
#include "MpvRenderThread.h"
#include "YtDlp.h"

#include <QCollator>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QQuickWindow>
#include <QSGSimpleTextureNode>
#include <QtQuick/qsgtexture_platform.h>
#include <QUrl>
#include <QtDebug>

#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <utility>
#include <vector>

// Общие данные элемента и рендерера. Колбэки mpv приходят из чужих потоков
// и могут сработать, пока элемент удаляется, поэтому указатель на элемент
// читается только под мьютексом, а вызовы ставятся в очередь GUI-потока
// (Qt выбрасывает их сам, если элемент уже удалён).
struct MpvBridge
{
    std::mutex mutex;
    MpvObject* item = nullptr;
    std::atomic_bool eventsQueued{false};

    void requestUpdate()
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (item)
            QMetaObject::invokeMethod(item, [i = item] { i->update(); }, Qt::QueuedConnection);
    }

    void requestRenderReady()
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (item)
            QMetaObject::invokeMethod(item, [i = item] { i->onRenderReady(); }, Qt::QueuedConnection);
    }

    void requestEvents()
    {
        if (eventsQueued.exchange(true))
            return;  // обработка уже запланирована
        std::lock_guard<std::mutex> lock(mutex);
        if (item)
            QMetaObject::invokeMethod(item, [i = item] { i->processEvents(); }, Qt::QueuedConnection);
    }
};

namespace {

QVariant nodeToVariant(const mpv_node* node)
{
    switch (node->format) {
    case MPV_FORMAT_STRING:
        return QString::fromUtf8(node->u.string);
    case MPV_FORMAT_FLAG:
        return node->u.flag != 0;
    case MPV_FORMAT_INT64:
        return QVariant::fromValue<qlonglong>(node->u.int64);
    case MPV_FORMAT_DOUBLE:
        return node->u.double_;
    case MPV_FORMAT_NODE_ARRAY: {
        QVariantList list;
        for (int i = 0; i < node->u.list->num; ++i)
            list.append(nodeToVariant(&node->u.list->values[i]));
        return list;
    }
    case MPV_FORMAT_NODE_MAP: {
        QVariantMap map;
        for (int i = 0; i < node->u.list->num; ++i)
            map.insert(QString::fromUtf8(node->u.list->keys[i]), nodeToVariant(&node->u.list->values[i]));
        return map;
    }
    default:
        return {};
    }
}

// Пути и file:///-URL → нативный путь; ссылки остаются как есть.
QString normalizeSource(const QString& source)
{
    QString s = source.trimmed();
    if (s.size() >= 2 && s.startsWith(QLatin1Char('"')) && s.endsWith(QLatin1Char('"')))
        s = s.mid(1, s.size() - 2);  // «Копировать как путь» в проводнике
    const QUrl url(s);
    if (url.isLocalFile())
        return QDir::toNativeSeparators(url.toLocalFile());
    return s;
}

// Номер дорожки из свойства aid/sid: число либо "no"/"auto"
int trackIdFromVariant(const QVariant& v)
{
    return v.typeId() == QMetaType::LongLong ? v.toInt() : -1;
}

template <typename T>
void assign(MpvObject* obj, T& field, const T& value, void (MpvObject::*signal)())
{
    if (field == value)
        return;
    field = value;
    (obj->*signal)();
}

// Узел сцены с текущим кадром видео. QSGTexture — лишь обёртка над
// GL-текстурой потока mpv (не владеет ей), её меняем на каждом новом кадре.
class VideoNode : public QSGSimpleTextureNode
{
public:
    void setFrameTexture(QSGTexture* texture)
    {
        setTexture(texture);
        m_texture.reset(texture);
    }

private:
    std::unique_ptr<QSGTexture> m_texture;
};
} // namespace

MpvObject::MpvObject(QQuickItem* parent)
    : QQuickItem(parent), m_bridge(std::make_shared<MpvBridge>())
{
    setFlag(ItemHasContents);

    // Поверхность для контекста потока mpv; создаётся только в GUI-потоке
    m_surface = new QOffscreenSurface;
    m_surface->setFormat(QSurfaceFormat::defaultFormat());
    m_surface->create();

    mpv_handle* handle = mpv_create();
    if (!handle)
        qFatal("mpv_create() failed");
    m_mpv = std::shared_ptr<mpv_handle>(handle, mpv_terminate_destroy);
    m_bridge->item = this;

    auto setOption = [handle](const char* name, const QString& value) {
        if (mpv_set_option_string(handle, name, value.toUtf8().constData()) < 0)
            qWarning() << "mpv: не удалось установить опцию" << name << "=" << value;
    };

    setOption("vo", QStringLiteral("libmpv"));
    setOption("hwdec", QStringLiteral("auto-safe"));
    setOption("keep-open", QStringLiteral("yes"));
    setOption("background-color", QStringLiteral("#0a0a0a"));  // цвет фона темы
    setOption("idle", QStringLiteral("yes"));
    setOption("input-default-bindings", QStringLiteral("no"));
    setOption("input-vo-keyboard", QStringLiteral("no"));
    setOption("sub-auto", QStringLiteral("fuzzy"));
    setOption("audio-file-auto", QStringLiteral("fuzzy"));
    setOption("demuxer-max-bytes", QStringLiteral("256MiB"));
    setOption("demuxer-max-back-bytes", QStringLiteral("64MiB"));
    setOption("ytdl", QStringLiteral("yes"));

    // yt-dlp, лежащий рядом с exe, используется встроенным ytdl_hook mpv
    const QString ytdlp = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("yt-dlp.exe"));
    if (QFileInfo::exists(ytdlp))
        setOption("script-opts", QStringLiteral("ytdl_hook-ytdl_path=") + QDir::toNativeSeparators(ytdlp));

    mpv_request_log_messages(handle, "warn");

    if (mpv_initialize(handle) < 0)
        qFatal("mpv_initialize() failed");

    static const char* const observed[] = {
        "idle-active", "media-title", "time-pos", "duration", "pause", "volume", "mute",
        "audio-delay", "paused-for-cache", "track-list", "aid", "sid", "demuxer-cache-time",
        "speed", "chapter-list", "chapter", "playlist", "playlist-pos",
    };
    for (const char* name : observed)
        mpv_observe_property(handle, 0, name, MPV_FORMAT_NODE);

    // Раньше ytdl_hook (у него приоритет 10): он читает ytdl-format,
    // который prepareFile ставит для пар «видео + аудио»
    mpv_hook_add(handle, 0, "on_load", 5);

    mpv_set_wakeup_callback(
        handle, [](void* bridge) { static_cast<MpvBridge*>(bridge)->requestEvents(); }, m_bridge.get());
    // События, накопившиеся до установки колбэка (начальные значения свойств)
    m_bridge->requestEvents();
}

MpvObject::~MpvObject()
{
    {
        std::lock_guard<std::mutex> lock(m_bridge->mutex);
        m_bridge->item = nullptr;
    }
    mpv_set_wakeup_callback(m_mpv.get(), nullptr, nullptr);
    // Поток освобождает render context, пока mpv_handle ещё жив (m_mpv
    // уничтожится, когда его отпустит и поток)
    delete m_renderThread;
    delete m_surface;
}

// ---------------------------------------------------------------------------
// Видео в сцене
// ---------------------------------------------------------------------------

void MpvObject::startRenderThread()
{
    // Вызывается в потоке рендера Qt Quick: здесь текущий его GL-контекст,
    // с ним и делим ресурсы, чтобы текстуры mpv были видны сцене
    QOpenGLContext* qtContext = QOpenGLContext::currentContext();
    if (!qtContext || !m_surface || !m_surface->isValid())
        return;

    auto* context = new QOpenGLContext;
    context->setFormat(qtContext->format());
    context->setShareContext(qtContext);
    if (!context->create()) {
        qCritical("mpv: не удалось создать общий OpenGL-контекст");
        delete context;
        return;
    }

    std::shared_ptr<MpvBridge> bridge = m_bridge;
    m_renderThread = new MpvRenderThread(m_mpv, context, m_surface, [bridge] { bridge->requestRenderReady(); },
                                         [bridge] { bridge->requestUpdate(); });
    context->moveToThread(m_renderThread);
    m_renderThread->start();
}

QSGNode* MpvObject::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*)
{
    if (!m_renderThread)
        startRenderThread();
    if (!m_renderThread)
        return oldNode;

    const qreal dpr = window() ? window()->effectiveDevicePixelRatio() : 1.0;
    m_renderThread->setTargetSize((size() * dpr).toSize());

    auto* node = static_cast<VideoNode*>(oldNode);
    MpvRenderThread::Frame frame;
    if (m_renderThread->takeFrame(&frame)) {
        if (frame.fence) {
            // Ожидание на стороне GPU: процессор не стоит, сцена просто
            // начнёт читать текстуру после того, как mpv её дорисует
            QOpenGLExtraFunctions* gl = QOpenGLContext::currentContext()->extraFunctions();
            gl->glWaitSync(frame.fence, 0, GL_TIMEOUT_IGNORED);
            gl->glDeleteSync(frame.fence);
        }
        if (!node) {
            node = new VideoNode;
            node->setFiltering(QSGTexture::Linear);
        }
        node->setFrameTexture(QNativeInterface::QSGOpenGLTexture::fromNative(frame.texture, window(), frame.size));
    }
    if (node)
        node->setRect(boundingRect());
    return node;
}

void MpvObject::itemChange(ItemChange change, const ItemChangeData& value)
{
    QQuickItem::itemChange(change, value);
    if (change == ItemSceneChange || change == ItemDevicePixelRatioHasChanged)
        update();
}

void MpvObject::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        update();  // новый размер кадра уйдёт в поток в updatePaintNode
}

// ---------------------------------------------------------------------------
// События mpv
// ---------------------------------------------------------------------------

void MpvObject::processEvents()
{
    m_bridge->eventsQueued = false;
    for (;;) {
        mpv_event* event = mpv_wait_event(m_mpv.get(), 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;
        handleEvent(*event);
    }
}

void MpvObject::handleEvent(const mpv_event& event)
{
    switch (event.event_id) {
    case MPV_EVENT_PROPERTY_CHANGE: {
        const auto* prop = static_cast<const mpv_event_property*>(event.data);
        QVariant value;
        if (prop->format == MPV_FORMAT_NODE)
            value = nodeToVariant(static_cast<const mpv_node*>(prop->data));
        handlePropertyChange(prop->name, value);
        break;
    }
    case MPV_EVENT_START_FILE:
        setLoading(true);
        break;
    case MPV_EVENT_FILE_LOADED:
        setLoading(false);
        if (!m_currentPairAudio.isEmpty())
            selectExternalAudio(m_currentPairAudio);
        emit fileLoaded();
        break;
    case MPV_EVENT_HOOK: {
        const auto* hook = static_cast<const mpv_event_hook*>(event.data);
        if (std::strcmp(hook->name, "on_load") == 0)
            prepareFile();
        mpv_hook_continue(m_mpv.get(), hook->id);
        break;
    }
    case MPV_EVENT_END_FILE: {
        const auto* end = static_cast<const mpv_event_end_file*>(event.data);
        if (end->reason == MPV_END_FILE_REASON_ERROR) {
            setLoading(false);
            QString reason;
            switch (end->error) {
            case MPV_ERROR_LOADING_FAILED:
                reason = tr("не удалось загрузить источник");
                break;
            case MPV_ERROR_UNKNOWN_FORMAT:
                reason = tr("неподдерживаемый формат");
                break;
            case MPV_ERROR_NOTHING_TO_PLAY:
                reason = tr("нечего воспроизводить");
                break;
            default:
                reason = QString::fromUtf8(mpv_error_string(end->error));
            }
            emit errorOccurred(tr("Ошибка воспроизведения: %1%2").arg(reason, lastErrorSuffix()));
        }
        break;
    }
    case MPV_EVENT_LOG_MESSAGE: {
        const auto* msg = static_cast<const mpv_event_log_message*>(event.data);
        const QString text = QString::fromUtf8(msg->text).trimmed();
        qWarning().noquote() << QStringLiteral("[mpv/%1] %2").arg(QString::fromUtf8(msg->prefix), text);
        if (msg->log_level <= MPV_LOG_LEVEL_ERROR)
            m_lastLogError = text;
        break;
    }
    default:
        break;
    }
}

void MpvObject::handlePropertyChange(const char* name, const QVariant& value)
{
    if (std::strcmp(name, "time-pos") == 0) {
        assign(this, m_position, value.toDouble(), &MpvObject::positionChanged);
    } else if (std::strcmp(name, "duration") == 0) {
        assign(this, m_duration, value.toDouble(), &MpvObject::durationChanged);
    } else if (std::strcmp(name, "demuxer-cache-time") == 0) {
        assign(this, m_cachedUntil, value.toDouble(), &MpvObject::cachedUntilChanged);
    } else if (std::strcmp(name, "pause") == 0) {
        assign(this, m_paused, value.toBool(), &MpvObject::pausedChanged);
    } else if (std::strcmp(name, "volume") == 0) {
        assign(this, m_volume, value.toDouble(), &MpvObject::volumeChanged);
    } else if (std::strcmp(name, "mute") == 0) {
        assign(this, m_muted, value.toBool(), &MpvObject::mutedChanged);
    } else if (std::strcmp(name, "audio-delay") == 0) {
        assign(this, m_audioDelay, value.toDouble(), &MpvObject::audioDelayChanged);
    } else if (std::strcmp(name, "speed") == 0) {
        assign(this, m_speed, value.isValid() ? value.toDouble() : 1.0, &MpvObject::speedChanged);
    } else if (std::strcmp(name, "playlist") == 0) {
        updatePlaylist(value.toList());
    } else if (std::strcmp(name, "playlist-pos") == 0) {
        assign(this, m_playlistPos, value.isValid() ? value.toInt() : -1, &MpvObject::playlistPosChanged);
    } else if (std::strcmp(name, "chapter-list") == 0) {
        updateChapters(value.toList());
    } else if (std::strcmp(name, "chapter") == 0) {
        assign(this, m_chapter, value.isValid() ? value.toInt() : -1, &MpvObject::chapterChanged);
    } else if (std::strcmp(name, "media-title") == 0) {
        assign(this, m_mediaTitle, value.toString(), &MpvObject::mediaTitleChanged);
    } else if (std::strcmp(name, "idle-active") == 0) {
        assign(this, m_idle, value.toBool(), &MpvObject::idleChanged);
    } else if (std::strcmp(name, "paused-for-cache") == 0) {
        assign(this, m_buffering, value.toBool(), &MpvObject::bufferingChanged);
    } else if (std::strcmp(name, "track-list") == 0) {
        updateTracks(value.toList());
    } else if (std::strcmp(name, "aid") == 0) {
        assign(this, m_audioId, trackIdFromVariant(value), &MpvObject::audioIdChanged);
    } else if (std::strcmp(name, "sid") == 0) {
        assign(this, m_subtitleId, trackIdFromVariant(value), &MpvObject::subtitleIdChanged);
    }
}

void MpvObject::updateTracks(const QVariantList& trackList)
{
    QVariantList audio;
    QVariantList subs;

    for (const QVariant& item : trackList) {
        const QVariantMap track = item.toMap();
        const QString type = track.value(QStringLiteral("type")).toString();
        const bool isAudio = type == QLatin1String("audio");
        if (!isAudio && type != QLatin1String("sub"))
            continue;

        const int id = track.value(QStringLiteral("id")).toInt();
        const bool external = track.value(QStringLiteral("external")).toBool();
        QString title = track.value(QStringLiteral("title")).toString();
        if (external && title.contains(QLatin1String("://")))
            title.clear();  // у внешних дорожек по ссылке title — это длинный URL
        if (title.isEmpty())
            title = external ? tr("Внешняя дорожка") : tr("Дорожка %1").arg(id);

        QStringList details;
        const QString lang = track.value(QStringLiteral("lang")).toString();
        if (!lang.isEmpty())
            details << lang.toUpper();
        const QString codec = track.value(QStringLiteral("codec")).toString();
        if (!codec.isEmpty())
            details << codec;
        if (isAudio) {
            const QString channels = track.value(QStringLiteral("demux-channels")).toString();
            if (!channels.isEmpty())
                details << channels;
        }
        if (external)
            details << tr("внешняя");

        const QVariantMap entry{
            {QStringLiteral("id"), id},
            {QStringLiteral("label"), title},
            {QStringLiteral("detail"), details.join(QStringLiteral(" · "))},
            {QStringLiteral("external"), external},
        };
        (isAudio ? audio : subs).append(entry);
    }

    m_audioTracks = audio;
    m_subtitleTracks = subs;
    emit tracksChanged();
}

void MpvObject::updateChapters(const QVariantList& chapterList)
{
    QVariantList chapters;
    for (const QVariant& item : chapterList) {
        const QVariantMap chapter = item.toMap();
        QString title = chapter.value(QStringLiteral("title")).toString();
        if (title.isEmpty())
            title = tr("Глава %1").arg(chapters.size() + 1);
        chapters.append(QVariantMap{
            {QStringLiteral("title"), title},
            {QStringLiteral("time"), chapter.value(QStringLiteral("time")).toDouble()},
        });
    }
    if (chapters == m_chapters)
        return;
    m_chapters = chapters;
    emit chaptersChanged();
}

void MpvObject::selectExternalAudio(const QString& source)
{
    // track-list запрашиваем напрямую: событие об его изменении может прийти
    // уже после FILE_LOADED.
    const QVariantList tracks = getProperty("track-list").toList();
    int fallbackId = -1;
    for (const QVariant& item : tracks) {
        const QVariantMap track = item.toMap();
        if (track.value(QStringLiteral("type")).toString() != QLatin1String("audio")
            || !track.value(QStringLiteral("external")).toBool())
            continue;
        const int id = track.value(QStringLiteral("id")).toInt();
        if (track.value(QStringLiteral("external-filename")).toString() == source) {
            setAudioTrack(id);
            return;
        }
        if (fallbackId < 0)
            fallbackId = id;
    }
    if (fallbackId >= 0) {
        setAudioTrack(fallbackId);
        return;
    }
    emit errorOccurred(tr("Не удалось загрузить аудио из второй ссылки%1").arg(lastErrorSuffix()));
}

void MpvObject::setLoading(bool loading)
{
    assign(this, m_loading, loading, &MpvObject::loadingChanged);
}

QString MpvObject::lastErrorSuffix() const
{
    return m_lastLogError.isEmpty() ? QString() : QStringLiteral("\n") + m_lastLogError;
}

// ---------------------------------------------------------------------------
// Загрузка
// ---------------------------------------------------------------------------

// Хук on_load: файл из очереди вот-вот откроется (через open, автопереход
// или выбор в очереди). Всё, что зависит от файла, ставим здесь опциями
// самого файла (file-local-options) — иначе они перешли бы на следующие.
void MpvObject::prepareFile()
{
    m_lastLogError.clear();
    const QString path = getProperty("path").toString();
    const QString audio = m_pairAudio.value(path);
    m_currentPairAudio = audio;

    auto setLocal = [this](const char* name, const QString& value) {
        const QByteArray key = QByteArray("file-local-options/") + name;
        mpv_set_property_string(m_mpv.get(), key.constData(), value.toUtf8().constData());
    };

    // Многие CDN (например, за ddos-guard) отдают прямые ссылки только при
    // наличии Referer, а mpv по умолчанию его не шлёт. Для прямых ссылок на
    // медиафайл подставляем домен самой ссылки; страницы сайтов не трогаем —
    // для них нужные заголовки выставляет ytdl_hook.
    const QUrl url(path);
    if (YtDlp::isMediaUrl(url))
        setLocal("referrer", url.adjusted(QUrl::RemovePath | QUrl::RemoveQuery | QUrl::RemoveFragment
                                          | QUrl::RemoveUserInfo).toString() + QLatin1Char('/'));

    if (!audio.isEmpty()) {
        // Звук берётся из второй ссылки — с сайта качаем только видео.
        // audio-delay не сбрасываем: у пары релизов сдвиг обычно одинаковый.
        setStringList("file-local-options/audio-files", {audio});
        setLocal("ytdl-format", QStringLiteral("bestvideo/best"));
    } else {
        setAudioDelay(0);
    }

    // Выбор дорожек — глобальная опция: сбрасываем, чтобы номер дорожки
    // из прошлого файла не применился к новому.
    mpv_set_property_string(m_mpv.get(), "aid", "auto");
    mpv_set_property_string(m_mpv.get(), "sid", "auto");

    // QML может попросить начать не с начала (setStartPosition)
    m_hookStart = 0;
    emit fileStarting(path);
    if (m_hookStart > 0)
        setLocal("start", QString::number(m_hookStart, 'f', 3));
    m_hookStart = 0;
}

void MpvObject::setStartPosition(double seconds)
{
    m_hookStart = seconds;
}

QString MpvObject::normalizedSource(const QString& source) const
{
    return normalizeSource(source);
}

void MpvObject::open(const QString& source, bool withFolder)
{
    const QString path = normalizeSource(source);
    if (path.isEmpty())
        return;

    m_pairAudio.remove(path);
    loadFile(path, QStringLiteral("replace"));
    if (withFolder && m_autoloadFolder)
        queueFolder(path);
}

void MpvObject::openWithAudio(const QString& video, const QString& audio)
{
    const QString videoPath = normalizeSource(video);
    const QString audioPath = normalizeSource(audio);
    if (videoPath.isEmpty())
        return;
    if (audioPath.isEmpty()) {
        open(videoPath);
        return;
    }

    m_pairAudio.insert(videoPath, audioPath);
    loadFile(videoPath, QStringLiteral("replace"));
}

void MpvObject::enqueue(const QString& source)
{
    const QString path = normalizeSource(source);
    if (path.isEmpty())
        return;
    m_pairAudio.remove(path);
    loadFile(path, m_idle && m_pendingLoads.isEmpty() ? QStringLiteral("append-play") : QStringLiteral("append"));
}

void MpvObject::enqueueWithAudio(const QString& video, const QString& audio)
{
    const QString videoPath = normalizeSource(video);
    const QString audioPath = normalizeSource(audio);
    if (videoPath.isEmpty())
        return;
    if (audioPath.isEmpty()) {
        enqueue(videoPath);
        return;
    }
    m_pairAudio.insert(videoPath, audioPath);
    loadFile(videoPath, m_idle && m_pendingLoads.isEmpty() ? QStringLiteral("append-play") : QStringLiteral("append"));
}

// Остальные видео из папки файла — в очередь до и после него, по порядку
// имён с учётом чисел (2 < 10), как autoload.lua в mpv
void MpvObject::queueFolder(const QString& path)
{
    const QFileInfo info(path);
    if (!info.isFile())
        return;

    static const QStringList filters{
        QStringLiteral("*.mkv"), QStringLiteral("*.mp4"), QStringLiteral("*.avi"), QStringLiteral("*.webm"),
        QStringLiteral("*.mov"), QStringLiteral("*.m2ts"), QStringLiteral("*.ts"), QStringLiteral("*.flv"),
        QStringLiteral("*.wmv"), QStringLiteral("*.m4v"),
    };
    const QDir dir = info.dir();
    QStringList files = dir.entryList(filters, QDir::Files);
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(files.begin(), files.end(), collator);

    const int self = files.indexOf(info.fileName());
    if (self < 0)
        return;
    for (int i = 0; i < files.size(); ++i) {
        if (i == self)
            continue;
        const QString file = QDir::toNativeSeparators(dir.filePath(files[i]));
        m_pairAudio.remove(file);
        if (i < self)
            loadFile(file, QStringLiteral("insert-at"), i);
        else
            loadFile(file, QStringLiteral("append"));
    }
}

// Пока поток отрисовки не создал render context, vo mpv не инициализируется
// и файл откроется без видео — поэтому loadfile откладываем до готовности.
void MpvObject::loadFile(const QString& path, const QString& flags, int index)
{
    QStringList args{QStringLiteral("loadfile"), path, flags};
    if (index >= 0)
        args << QString::number(index);
    if (!m_renderReady) {
        if (flags == QLatin1String("replace"))
            m_pendingLoads.clear();
        m_pendingLoads.append(args);
        update();  // первый updatePaintNode запустит поток отрисовки
        return;
    }
    command(args);
}

void MpvObject::onRenderReady()
{
    m_renderReady = true;
    const QList<QStringList> loads = std::exchange(m_pendingLoads, {});
    for (const QStringList& args : loads)
        command(args);
}

// ---------------------------------------------------------------------------
// Очередь
// ---------------------------------------------------------------------------

void MpvObject::playlistNext()
{
    command({QStringLiteral("playlist-next")});
}

void MpvObject::playlistPrev()
{
    command({QStringLiteral("playlist-prev")});
}

void MpvObject::playlistPlay(int index)
{
    command({QStringLiteral("playlist-play-index"), QString::number(index)});
}

void MpvObject::playlistRemove(int index)
{
    command({QStringLiteral("playlist-remove"), QString::number(index)});
}

void MpvObject::playlistMove(int from, int before)
{
    command({QStringLiteral("playlist-move"), QString::number(from), QString::number(before)});
}

void MpvObject::playlistClearOthers()
{
    command({QStringLiteral("playlist-clear")});
}

void MpvObject::setAutoloadFolder(bool enabled)
{
    assign(this, m_autoloadFolder, enabled, &MpvObject::autoloadFolderChanged);
}

void MpvObject::updatePlaylist(const QVariantList& list)
{
    QVariantList items;
    for (const QVariant& item : list) {
        const QVariantMap entry = item.toMap();
        items.append(QVariantMap{
            {QStringLiteral("source"), entry.value(QStringLiteral("filename")).toString()},
            {QStringLiteral("title"), entry.value(QStringLiteral("title")).toString()},
            {QStringLiteral("current"), entry.value(QStringLiteral("current")).toBool()},
        });
    }
    if (items == m_playlist)
        return;
    m_playlist = items;
    emit playlistChanged();
}

void MpvObject::addAudio(const QString& source)
{
    const QString path = normalizeSource(source);
    if (!path.isEmpty())
        command({QStringLiteral("audio-add"), path, QStringLiteral("select")});
}

void MpvObject::addSubtitle(const QString& source)
{
    const QString path = normalizeSource(source);
    if (!path.isEmpty())
        command({QStringLiteral("sub-add"), path, QStringLiteral("select")});
}

// ---------------------------------------------------------------------------
// Управление
// ---------------------------------------------------------------------------

void MpvObject::togglePause()
{
    command({QStringLiteral("cycle"), QStringLiteral("pause")});
}

void MpvObject::seek(double seconds, bool exact)
{
    command({QStringLiteral("seek"), QString::number(seconds, 'f', 3),
             exact ? QStringLiteral("absolute+exact") : QStringLiteral("absolute+keyframes")});
}

void MpvObject::seekRelative(double seconds)
{
    command({QStringLiteral("seek"), QString::number(seconds, 'f', 3), QStringLiteral("relative+exact")});
}

void MpvObject::seekChapter(int delta)
{
    command({QStringLiteral("add"), QStringLiteral("chapter"), QString::number(delta)});
}

void MpvObject::setAudioTrack(int id)
{
    const QByteArray value = id < 0 ? QByteArray("no") : QByteArray::number(id);
    mpv_set_property_string(m_mpv.get(), "aid", value.constData());
}

void MpvObject::setSubtitleTrack(int id)
{
    const QByteArray value = id < 0 ? QByteArray("no") : QByteArray::number(id);
    mpv_set_property_string(m_mpv.get(), "sid", value.constData());
}

void MpvObject::setPaused(bool paused)
{
    int flag = paused ? 1 : 0;
    mpv_set_property(m_mpv.get(), "pause", MPV_FORMAT_FLAG, &flag);
}

void MpvObject::setVolume(double volume)
{
    mpv_set_property(m_mpv.get(), "volume", MPV_FORMAT_DOUBLE, &volume);
}

void MpvObject::setMuted(bool muted)
{
    int flag = muted ? 1 : 0;
    mpv_set_property(m_mpv.get(), "mute", MPV_FORMAT_FLAG, &flag);
}

void MpvObject::setAudioDelay(double seconds)
{
    mpv_set_property(m_mpv.get(), "audio-delay", MPV_FORMAT_DOUBLE, &seconds);
}

void MpvObject::setSpeed(double speed)
{
    mpv_set_property(m_mpv.get(), "speed", MPV_FORMAT_DOUBLE, &speed);
}

void MpvObject::setHwdec(bool enabled)
{
    mpv_set_property_string(m_mpv.get(), "hwdec", enabled ? "auto-safe" : "no");
    assign(this, m_hwdec, enabled, &MpvObject::hwdecChanged);
}

// ---------------------------------------------------------------------------
// Anime4K
// ---------------------------------------------------------------------------

void MpvObject::setShaderPreset(const QString& preset)
{
    const QStringList files = Anime4K::shaderFiles(preset, m_anime4kFast);
    if (files.isEmpty()) {
        setStringList("glsl-shaders", {});
        assign(this, m_shaderPreset, QStringLiteral("off"), &MpvObject::shaderPresetChanged);
        return;
    }

    const QDir dir(QCoreApplication::applicationDirPath() + QStringLiteral("/shaders"));
    QStringList paths;
    QStringList missing;
    for (const QString& file : files) {
        const QString path = dir.filePath(file);
        if (QFileInfo::exists(path))
            paths << QDir::toNativeSeparators(path);
        else
            missing << file;
    }

    if (!missing.isEmpty()) {
        emit errorOccurred(tr("Anime4K: не найдены шейдеры в %1:\n%2")
                               .arg(QDir::toNativeSeparators(dir.path()), missing.join(QStringLiteral(", "))));
        return;
    }

    if (setStringList("glsl-shaders", paths) < 0) {
        emit errorOccurred(tr("Anime4K: mpv не принял шейдеры"));
        return;
    }
    assign(this, m_shaderPreset, preset, &MpvObject::shaderPresetChanged);
}

void MpvObject::setAnime4kFast(bool fast)
{
    if (m_anime4kFast == fast)
        return;
    m_anime4kFast = fast;
    emit anime4kFastChanged();
    if (m_shaderPreset != QLatin1String("off"))
        setShaderPreset(m_shaderPreset);  // пересобрать цепочку
}

// ---------------------------------------------------------------------------
// Сведения о файле
// ---------------------------------------------------------------------------

namespace {

QString codecName(const QString& codec)
{
    static const QHash<QString, QString> names{
        {QStringLiteral("h264"), QStringLiteral("H.264 (AVC)")},
        {QStringLiteral("hevc"), QStringLiteral("H.265 (HEVC)")},
        {QStringLiteral("av1"), QStringLiteral("AV1")},
        {QStringLiteral("vp8"), QStringLiteral("VP8")},
        {QStringLiteral("vp9"), QStringLiteral("VP9")},
        {QStringLiteral("mpeg2video"), QStringLiteral("MPEG-2")},
        {QStringLiteral("mpeg4"), QStringLiteral("MPEG-4 Part 2")},
        {QStringLiteral("aac"), QStringLiteral("AAC")},
        {QStringLiteral("opus"), QStringLiteral("Opus")},
        {QStringLiteral("vorbis"), QStringLiteral("Vorbis")},
        {QStringLiteral("flac"), QStringLiteral("FLAC")},
        {QStringLiteral("mp3"), QStringLiteral("MP3")},
        {QStringLiteral("ac3"), QStringLiteral("Dolby Digital (AC-3)")},
        {QStringLiteral("eac3"), QStringLiteral("Dolby Digital Plus (E-AC-3)")},
        {QStringLiteral("truehd"), QStringLiteral("Dolby TrueHD")},
        {QStringLiteral("dts"), QStringLiteral("DTS")},
        {QStringLiteral("ass"), QStringLiteral("ASS")},
        {QStringLiteral("ssa"), QStringLiteral("SSA")},
        {QStringLiteral("subrip"), QStringLiteral("SRT")},
        {QStringLiteral("webvtt"), QStringLiteral("WebVTT")},
        {QStringLiteral("hdmv_pgs_subtitle"), QStringLiteral("PGS")},
        {QStringLiteral("dvd_subtitle"), QStringLiteral("VobSub")},
    };
    if (codec.startsWith(QLatin1String("pcm_")))
        return QStringLiteral("PCM");
    return names.value(codec, codec.toUpper());
}

QString formatSize(double bytes)
{
    if (bytes >= 1024.0 * 1024 * 1024)
        return MpvObject::tr("%1 ГБ").arg(bytes / (1024.0 * 1024 * 1024), 0, 'f', 2);
    if (bytes >= 1024.0 * 1024)
        return MpvObject::tr("%1 МБ").arg(bytes / (1024.0 * 1024), 0, 'f', 1);
    return MpvObject::tr("%1 КБ").arg(qRound(bytes / 1024.0));
}

QString formatBitrate(double bitsPerSecond)
{
    if (bitsPerSecond >= 1e6)
        return MpvObject::tr("%1 Мбит/с").arg(bitsPerSecond / 1e6, 0, 'f', 1);
    return MpvObject::tr("%1 кбит/с").arg(qRound(bitsPerSecond / 1e3));
}

QString formatDuration(double seconds)
{
    const qint64 s = qint64(seconds);
    const QString sec = QStringLiteral("%1").arg(s % 60, 2, 10, QLatin1Char('0'));
    if (s < 3600)
        return QStringLiteral("%1:%2").arg(s / 60).arg(sec);
    return QStringLiteral("%1:%2:%3").arg(s / 3600).arg((s % 3600) / 60, 2, 10, QLatin1Char('0')).arg(sec);
}

// Число без лишних нулей: 23.976, 24, 29.97
QString trimmedNumber(double value, int decimals)
{
    QString text = QString::number(value, 'f', decimals);
    if (text.contains(QLatin1Char('.'))) {
        while (text.endsWith(QLatin1Char('0')))
            text.chop(1);
        if (text.endsWith(QLatin1Char('.')))
            text.chop(1);
    }
    return text;
}

// Глубина цвета по формату пикселей: yuv420p10 / p010 → 10, nv12 / yuv420p → 8
int bitDepth(const QString& pixfmt)
{
    static const QRegularExpression suffix(QStringLiteral("p(\\d{1,2})(le|be)?$"));
    static const QRegularExpression packed(QStringLiteral("^p0?(\\d{2})"));
    QRegularExpressionMatch m = packed.match(pixfmt);
    if (m.hasMatch())
        return m.captured(1).toInt();
    m = suffix.match(pixfmt);
    if (m.hasMatch())
        return m.captured(1).toInt();
    if (pixfmt.startsWith(QLatin1String("nv")) || pixfmt.startsWith(QLatin1String("yuv"))
        || pixfmt.startsWith(QLatin1String("yuvj")))
        return 8;
    return 0;
}

QString trackName(const QVariantMap& track)
{
    QStringList parts;
    const QString title = track.value(QStringLiteral("title")).toString();
    if (!title.isEmpty() && !title.contains(QLatin1String("://")))
        parts << title;
    const QString lang = track.value(QStringLiteral("lang")).toString();
    if (!lang.isEmpty())
        parts << lang.toUpper();
    if (parts.isEmpty())
        parts << MpvObject::tr("Дорожка %1").arg(track.value(QStringLiteral("id")).toInt());
    return parts.join(QStringLiteral(" · "));
}

void addRow(QVariantList& rows, const QString& label, const QString& value)
{
    if (!value.isEmpty())
        rows.append(QVariantMap{{QStringLiteral("label"), label}, {QStringLiteral("value"), value}});
}

QVariantMap section(const QString& title, const QString& icon, const QVariantList& rows)
{
    return {{QStringLiteral("title"), title}, {QStringLiteral("icon"), icon}, {QStringLiteral("rows"), rows}};
}

} // namespace

QVariantMap MpvObject::currentTrack(const char* type) const
{
    return getProperty(QByteArray("current-tracks/").append(type).constData()).toMap();
}

QVariantList MpvObject::mediaInfo() const
{
    QVariantList sections;
    if (m_idle)
        return sections;

    const auto num = [this](const char* name) { return getProperty(name).toDouble(); };
    const auto text = [this](const char* name) { return getProperty(name).toString(); };

    // --- Файл ---
    QVariantList file;
    const QString path = text("path");
    const bool remote = path.contains(QLatin1String("://"));
    const QString filename = text("filename");
    if (m_mediaTitle != filename)
        addRow(file, tr("Название"), m_mediaTitle);
    if (remote) {
        addRow(file, tr("Ссылка"), path);
    } else {
        const QFileInfo info(path);
        addRow(file, tr("Файл"), info.fileName());
        addRow(file, tr("Папка"), QDir::toNativeSeparators(info.absolutePath()));
    }
    const double size = num("file-size");
    if (size > 0)
        addRow(file, tr("Размер"), formatSize(size));
    // mp4 mpv называет "mov,mp4,m4a,3gp,3g2,mj2"
    QString format = text("file-format");
    if (format.contains(QLatin1String("mp4")))
        format = QStringLiteral("mp4");
    addRow(file, tr("Контейнер"), format.toUpper());
    if (m_duration > 0)
        addRow(file, tr("Длительность"), formatDuration(m_duration));
    if (size > 0 && m_duration > 0)
        addRow(file, tr("Общий битрейт"), formatBitrate(size * 8 / m_duration));
    if (!m_chapters.isEmpty())
        addRow(file, tr("Главы"), QString::number(m_chapters.size()));
    sections.append(section(tr("Файл"), QStringLiteral("folder"), file));

    // --- Видео ---
    const QVariantMap video = currentTrack("video");
    if (!video.isEmpty()) {
        QVariantList rows;
        QString codec = codecName(video.value(QStringLiteral("codec")).toString());
        const QString profile = video.value(QStringLiteral("codec-profile")).toString();
        if (!profile.isEmpty())
            codec += QStringLiteral(" · ") + profile;
        addRow(rows, tr("Кодек"), codec);

        const int w = video.value(QStringLiteral("demux-w")).toInt();
        const int h = video.value(QStringLiteral("demux-h")).toInt();
        if (w > 0 && h > 0)
            addRow(rows, tr("Разрешение"), QStringLiteral("%1 × %2").arg(w).arg(h));

        double fps = video.value(QStringLiteral("demux-fps")).toDouble();
        if (fps <= 0)
            fps = num("container-fps");
        if (fps > 0)
            addRow(rows, tr("Частота кадров"), tr("%1 к/с").arg(trimmedNumber(fps, 3)));

        const double demuxBitrate = video.value(QStringLiteral("demux-bitrate")).toDouble();
        const double liveBitrate = num("video-bitrate");
        if (demuxBitrate > 0)
            addRow(rows, tr("Битрейт"), formatBitrate(demuxBitrate));
        else if (liveBitrate > 0)
            addRow(rows, tr("Битрейт"), QStringLiteral("≈ ") + formatBitrate(liveBitrate));

        const QVariantMap params = getProperty("video-params").toMap();
        QStringList color;
        QString pixfmt = params.value(QStringLiteral("hw-pixelformat")).toString();
        if (pixfmt.isEmpty())
            pixfmt = params.value(QStringLiteral("pixelformat")).toString();
        const int depth = bitDepth(pixfmt);
        if (depth > 0)
            color << tr("%1 бит").arg(depth);
        const QString gamma = params.value(QStringLiteral("gamma")).toString();
        if (gamma == QLatin1String("pq"))
            color << QStringLiteral("HDR10 (PQ)");
        else if (gamma == QLatin1String("hlg"))
            color << QStringLiteral("HDR (HLG)");
        else if (!params.isEmpty())
            color << QStringLiteral("SDR");
        const QString primaries = params.value(QStringLiteral("primaries")).toString();
        if (!primaries.isEmpty())
            color << primaries.toUpper();
        addRow(rows, tr("Цвет"), color.join(QStringLiteral(" · ")));

        const QString hwdec = text("hwdec-current");
        addRow(rows, tr("Декодирование"),
               hwdec.isEmpty() || hwdec == QLatin1String("no") ? tr("Программное")
                                                                 : tr("Аппаратное (%1)").arg(hwdec));
        if (m_shaderPreset != QLatin1String("off"))
            addRow(rows, QStringLiteral("Anime4K"), tr("Режим %1").arg(m_shaderPreset));
        sections.append(section(tr("Видео"), QStringLiteral("video"), rows));
    }

    // --- Аудио ---
    const QVariantMap audio = currentTrack("audio");
    {
        QVariantList rows;
        if (audio.isEmpty()) {
            addRow(rows, tr("Дорожка"), m_audioTracks.isEmpty() ? tr("Нет звука") : tr("Выключена"));
        } else {
            addRow(rows, tr("Дорожка"), trackName(audio));
            addRow(rows, tr("Кодек"), codecName(audio.value(QStringLiteral("codec")).toString()));
            const QString layout = audio.value(QStringLiteral("demux-channels")).toString();
            const int channels = audio.value(QStringLiteral("demux-channel-count")).toInt();
            if (channels > 0)
                addRow(rows, tr("Каналы"), layout.isEmpty() || layout == QString::number(channels)
                                               ? QString::number(channels)
                                               : QStringLiteral("%1 (%2)").arg(channels).arg(layout));
            const double rate = audio.value(QStringLiteral("demux-samplerate")).toDouble();
            if (rate > 0)
                addRow(rows, tr("Частота"), tr("%1 кГц").arg(trimmedNumber(rate / 1000, 1)));
            const double demuxBitrate = audio.value(QStringLiteral("demux-bitrate")).toDouble();
            const double liveBitrate = num("audio-bitrate");
            if (demuxBitrate > 0)
                addRow(rows, tr("Битрейт"), formatBitrate(demuxBitrate));
            else if (liveBitrate > 0)
                addRow(rows, tr("Битрейт"), QStringLiteral("≈ ") + formatBitrate(liveBitrate));
            if (audio.value(QStringLiteral("external")).toBool())
                addRow(rows, tr("Источник"), audio.value(QStringLiteral("external-filename")).toString());
        }
        if (m_audioTracks.size() > 1)
            addRow(rows, tr("Всего дорожек"), QString::number(m_audioTracks.size()));
        sections.append(section(tr("Аудио"), QStringLiteral("audio"), rows));
    }

    // --- Субтитры ---
    if (!m_subtitleTracks.isEmpty()) {
        QVariantList rows;
        const QVariantMap sub = currentTrack("sub");
        if (sub.isEmpty()) {
            addRow(rows, tr("Дорожка"), tr("Выключены"));
        } else {
            addRow(rows, tr("Дорожка"), trackName(sub));
            addRow(rows, tr("Формат"), codecName(sub.value(QStringLiteral("codec")).toString()));
            if (sub.value(QStringLiteral("external")).toBool())
                addRow(rows, tr("Источник"), sub.value(QStringLiteral("external-filename")).toString());
        }
        addRow(rows, tr("Всего дорожек"), QString::number(m_subtitleTracks.size()));
        sections.append(section(tr("Субтитры"), QStringLiteral("subtitles"), rows));
    }

    return sections;
}

// ---------------------------------------------------------------------------
// Низкоуровневый доступ к mpv
// ---------------------------------------------------------------------------

void MpvObject::command(const QStringList& args)
{
    std::vector<QByteArray> utf8;
    utf8.reserve(args.size());
    for (const QString& arg : args)
        utf8.push_back(arg.toUtf8());

    std::vector<const char*> argv;
    argv.reserve(utf8.size() + 1);
    for (const QByteArray& arg : utf8)
        argv.push_back(arg.constData());
    argv.push_back(nullptr);

    // Асинхронно: loadfile и seek не блокируют интерфейс
    mpv_command_async(m_mpv.get(), 0, argv.data());
}

void MpvObject::setMpvProperty(const QString& name, const QVariant& value)
{
    const QByteArray key = name.toUtf8();
    int rc = 0;
    switch (value.typeId()) {
    case QMetaType::Bool: {
        int flag = value.toBool() ? 1 : 0;
        rc = mpv_set_property(m_mpv.get(), key.constData(), MPV_FORMAT_FLAG, &flag);
        break;
    }
    case QMetaType::Int:
    case QMetaType::LongLong: {
        int64_t number = value.toLongLong();
        rc = mpv_set_property(m_mpv.get(), key.constData(), MPV_FORMAT_INT64, &number);
        break;
    }
    case QMetaType::Double: {
        double number = value.toDouble();
        rc = mpv_set_property(m_mpv.get(), key.constData(), MPV_FORMAT_DOUBLE, &number);
        break;
    }
    case QMetaType::QStringList:
    case QMetaType::QVariantList:
        rc = setStringList(key.constData(), value.toStringList());
        break;
    default:
        rc = mpv_set_property_string(m_mpv.get(), key.constData(), value.toString().toUtf8().constData());
    }
    if (rc < 0)
        qWarning() << "mpv: не удалось установить" << name << "=" << value << ":" << mpv_error_string(rc);
}

QVariant MpvObject::getProperty(const char* name) const
{
    mpv_node node;
    if (mpv_get_property(m_mpv.get(), name, MPV_FORMAT_NODE, &node) < 0)
        return {};
    QVariant result = nodeToVariant(&node);
    mpv_free_node_contents(&node);
    return result;
}

// Списочные опции (audio-files, glsl-shaders) передаём массивом mpv_node:
// так не нужно экранировать разделители в путях и URL.
int MpvObject::setStringList(const char* name, const QStringList& items)
{
    std::vector<QByteArray> utf8;
    utf8.reserve(items.size());
    for (const QString& item : items)
        utf8.push_back(item.toUtf8());

    std::vector<mpv_node> values(utf8.size());
    for (size_t i = 0; i < utf8.size(); ++i) {
        values[i].format = MPV_FORMAT_STRING;
        values[i].u.string = utf8[i].data();
    }

    mpv_node_list list{};
    list.num = static_cast<int>(values.size());
    list.values = values.data();

    mpv_node node{};
    node.format = MPV_FORMAT_NODE_ARRAY;
    node.u.list = &list;

    const int rc = mpv_set_property(m_mpv.get(), name, MPV_FORMAT_NODE, &node);
    if (rc < 0)
        qWarning() << "mpv: не удалось установить" << name << ":" << mpv_error_string(rc);
    return rc;
}
