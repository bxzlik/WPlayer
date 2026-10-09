#pragma once

#include <QHash>
#include <QQuickItem>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

#include <memory>

#include <mpv/client.h>

struct MpvBridge;
class MpvRenderThread;
class QOffscreenSurface;

// QML-элемент с видео mpv. mpv рисует через render API в своём потоке
// (MpvRenderThread), а элемент показывает готовый кадр как текстуру сцены —
// поверх можно накладывать любой интерфейс, и он не ждёт отрисовки видео.
class MpvObject : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool idle READ idle NOTIFY idleChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(bool buffering READ buffering NOTIFY bufferingChanged)
    Q_PROPERTY(QString mediaTitle READ mediaTitle NOTIFY mediaTitleChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    // До какого момента (с) уже загружен поток — для полосы буфера
    Q_PROPERTY(double cachedUntil READ cachedUntil NOTIFY cachedUntilChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)
    Q_PROPERTY(double audioDelay READ audioDelay WRITE setAudioDelay NOTIFY audioDelayChanged)
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY speedChanged)
    // Главы файла: [{ title, time }] и номер текущей (-1 — до первой или нет глав)
    Q_PROPERTY(QVariantList chapters READ chapters NOTIFY chaptersChanged)
    Q_PROPERTY(int chapter READ chapter NOTIFY chapterChanged)
    Q_PROPERTY(bool hwdec READ hwdec WRITE setHwdec NOTIFY hwdecChanged)
    Q_PROPERTY(QVariantList audioTracks READ audioTracks NOTIFY tracksChanged)
    Q_PROPERTY(QVariantList subtitleTracks READ subtitleTracks NOTIFY tracksChanged)
    Q_PROPERTY(int audioId READ audioId NOTIFY audioIdChanged)
    Q_PROPERTY(int subtitleId READ subtitleId NOTIFY subtitleIdChanged)
    Q_PROPERTY(QString shaderPreset READ shaderPreset NOTIFY shaderPresetChanged)
    Q_PROPERTY(bool anime4kFast READ anime4kFast WRITE setAnime4kFast NOTIFY anime4kFastChanged)
    // Очередь (плейлист mpv): [{ source, title, current }] и номер текущего
    Q_PROPERTY(QVariantList playlist READ playlist NOTIFY playlistChanged)
    Q_PROPERTY(int playlistPos READ playlistPos NOTIFY playlistPosChanged)
    // open() добавляет в очередь остальные видео из папки файла
    Q_PROPERTY(bool autoloadFolder READ autoloadFolder WRITE setAutoloadFolder NOTIFY autoloadFolderChanged)

public:
    explicit MpvObject(QQuickItem* parent = nullptr);
    ~MpvObject() override;


    bool idle() const { return m_idle; }
    bool loading() const { return m_loading; }
    bool buffering() const { return m_buffering; }
    QString mediaTitle() const { return m_mediaTitle; }
    double position() const { return m_position; }
    double duration() const { return m_duration; }
    double cachedUntil() const { return m_cachedUntil; }
    bool paused() const { return m_paused; }
    double volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    double audioDelay() const { return m_audioDelay; }
    double speed() const { return m_speed; }
    QVariantList chapters() const { return m_chapters; }
    int chapter() const { return m_chapter; }
    bool hwdec() const { return m_hwdec; }
    QVariantList audioTracks() const { return m_audioTracks; }
    QVariantList subtitleTracks() const { return m_subtitleTracks; }
    int audioId() const { return m_audioId; }
    int subtitleId() const { return m_subtitleId; }
    QString shaderPreset() const { return m_shaderPreset; }
    bool anime4kFast() const { return m_anime4kFast; }
    QVariantList playlist() const { return m_playlist; }
    int playlistPos() const { return m_playlistPos; }
    bool autoloadFolder() const { return m_autoloadFolder; }

    void setPaused(bool paused);
    void setVolume(double volume);
    void setMuted(bool muted);
    void setAudioDelay(double seconds);
    void setSpeed(double speed);
    void setHwdec(bool enabled);
    void setAnime4kFast(bool fast);
    void setAutoloadFolder(bool enabled);

    // source — путь, file:///-URL или ссылка (сайты открываются через yt-dlp).
    // Очередь заменяется; withFolder — с соседними видео из папки, если
    // включён autoloadFolder
    Q_INVOKABLE void open(const QString& source, bool withFolder = true);
    // Видео из video, звук из audio (через опцию mpv audio-files).
    // audio должен быть файлом или прямой ссылкой на поток — страницы сайтов
    // заранее разрешаются через YtDlp::resolveAudio.
    Q_INVOKABLE void openWithAudio(const QString& video, const QString& audio);
    // В конец очереди; если ничего не играет — сразу воспроизвести
    Q_INVOKABLE void enqueue(const QString& source);
    // Пара «видео + аудио» в конец очереди (audio — как у openWithAudio)
    Q_INVOKABLE void enqueueWithAudio(const QString& video, const QString& audio);
    // Вызывается из обработчика fileStarting: начать файл с этой секунды
    Q_INVOKABLE void setStartPosition(double seconds);
    // Источник в том виде, в каком его откроет mpv: file:///-URL и путь
    // в кавычках → нативный путь. Ключ записи в истории.
    Q_INVOKABLE QString normalizedSource(const QString& source) const;
    Q_INVOKABLE void addAudio(const QString& source);
    Q_INVOKABLE void addSubtitle(const QString& source);

    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void seek(double seconds, bool exact = true);
    Q_INVOKABLE void seekRelative(double seconds);
    // ±1 глава, как PgUp/PgDn в mpv: назад в первые секунды главы — к
    // предыдущей, позже — к началу текущей; вперёд с последней — в конец файла
    Q_INVOKABLE void seekChapter(int delta);
    Q_INVOKABLE void setAudioTrack(int id);     // -1 = выключить
    Q_INVOKABLE void setSubtitleTrack(int id);  // -1 = выключить

    Q_INVOKABLE void playlistNext();
    Q_INVOKABLE void playlistPrev();
    Q_INVOKABLE void playlistPlay(int index);
    Q_INVOKABLE void playlistRemove(int index);
    // Переставить запись from перед записью before (индексы до перестановки)
    Q_INVOKABLE void playlistMove(int from, int before);
    // Убрать всё, кроме текущего
    Q_INVOKABLE void playlistClearOthers();

    // "off", "A", "B", "C", "AA", "BB", "CA"
    Q_INVOKABLE void setShaderPreset(const QString& preset);

    // Сведения о текущем файле для окна «Инфо»:
    // [{ title, icon, rows: [{ label, value }] }] — уже в читаемом виде
    Q_INVOKABLE QVariantList mediaInfo() const;

    Q_INVOKABLE void command(const QStringList& args);
    Q_INVOKABLE void setMpvProperty(const QString& name, const QVariant& value);

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* data) override;
    void itemChange(ItemChange change, const ItemChangeData& value) override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

signals:
    void idleChanged();
    void loadingChanged();
    void bufferingChanged();
    void mediaTitleChanged();
    void positionChanged();
    void durationChanged();
    void cachedUntilChanged();
    void pausedChanged();
    void volumeChanged();
    void mutedChanged();
    void audioDelayChanged();
    void speedChanged();
    void chaptersChanged();
    void chapterChanged();
    void hwdecChanged();
    void tracksChanged();
    void audioIdChanged();
    void subtitleIdChanged();
    void shaderPresetChanged();
    void anime4kFastChanged();
    void playlistChanged();
    void playlistPosChanged();
    void autoloadFolderChanged();

    // Файл очереди начинает открываться (path — как в очереди). Обработчик
    // может вызвать setStartPosition — позиция применится к этому файлу.
    void fileStarting(const QString& path);

    void fileLoaded();
    void errorOccurred(const QString& message);

private:
    friend struct MpvBridge;

    void processEvents();
    void startRenderThread();
    void onRenderReady();
    void loadFile(const QString& path, const QString& flags, int index = -1);
    void queueFolder(const QString& path);
    void prepareFile();
    void updatePlaylist(const QVariantList& list);
    void handleEvent(const mpv_event& event);
    void handlePropertyChange(const char* name, const QVariant& value);
    void updateTracks(const QVariantList& trackList);
    void updateChapters(const QVariantList& chapterList);
    void selectExternalAudio(const QString& source);
    void setLoading(bool loading);

    QVariant getProperty(const char* name) const;
    QVariantMap currentTrack(const char* type) const;
    int setStringList(const char* name, const QStringList& items);
    QString lastErrorSuffix() const;

    std::shared_ptr<mpv_handle> m_mpv;
    std::shared_ptr<MpvBridge> m_bridge;
    QOffscreenSurface* m_surface = nullptr;
    MpvRenderThread* m_renderThread = nullptr;
    bool m_renderReady = false;
    QList<QStringList> m_pendingLoads;  // loadfile, ждущие готовности отрисовки

    QString m_lastLogError;
    // Пары «видео + аудио»: путь видео в очереди → звук из второй ссылки
    QHash<QString, QString> m_pairAudio;
    QString m_currentPairAudio;  // звук текущего файла, выбрать после загрузки
    double m_hookStart = 0;

    bool m_idle = true;
    bool m_loading = false;
    bool m_buffering = false;
    QString m_mediaTitle;
    double m_position = 0;
    double m_duration = 0;
    double m_cachedUntil = 0;
    bool m_paused = false;
    double m_volume = 100;
    bool m_muted = false;
    double m_audioDelay = 0;
    double m_speed = 1;
    QVariantList m_chapters;
    int m_chapter = -1;
    bool m_hwdec = true;
    QVariantList m_audioTracks;
    QVariantList m_subtitleTracks;
    int m_audioId = -1;
    int m_subtitleId = -1;
    QString m_shaderPreset = QStringLiteral("off");
    bool m_anime4kFast = false;
    QVariantList m_playlist;
    int m_playlistPos = -1;
    bool m_autoloadFolder = false;
};
