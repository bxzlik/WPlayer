#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QtQml/qqmlregistration.h>

class QNetworkAccessManager;
class QUrl;

// Обёртка над yt-dlp.exe: получение прямой ссылки на аудиопоток,
// обновление (yt-dlp -U) и первичное скачивание.
class YtDlp : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool resolving READ resolving NOTIFY resolvingChanged)
    Q_PROPERTY(QString version READ version NOTIFY versionChanged)
    Q_PROPERTY(bool bundled READ bundled NOTIFY versionChanged)

public:
    explicit YtDlp(QObject* parent = nullptr);

    bool busy() const { return m_busy; }
    bool resolving() const { return m_resolveProcess != nullptr; }
    QString version() const { return m_version; }
    bool bundled() const;  // yt-dlp.exe лежит рядом с плеером

    // true — источник можно отдать mpv напрямую (файл или ссылка на медиафайл/поток),
    // false — это страница сайта и её нужно разрешить через resolveAudio().
    Q_INVOKABLE bool isDirectMedia(const QString& source) const;
    // http(s)-ссылка, путь которой заканчивается расширением медиафайла
    static bool isMediaUrl(const QUrl& url);

    Q_INVOKABLE void resolveAudio(const QString& url);
    Q_INVOKABLE void cancelResolve();

    Q_INVOKABLE void refreshVersion();
    // Обновляет копию рядом с exe (yt-dlp -U) или скачивает её, если её нет
    Q_INVOKABLE void update();

signals:
    void busyChanged();
    void resolvingChanged();
    void versionChanged();

    void audioResolved(const QString& source, const QString& directUrl);
    void resolveFailed(const QString& message);
    void updateFinished(bool ok, const QString& message);

private:
    QString bundledPath() const;
    QString program() const;
    QProcess* makeProcess();
    void setBusy(bool busy);
    void download();

    QNetworkAccessManager* m_network = nullptr;
    QPointer<QProcess> m_resolveProcess;
    QString m_version;
    bool m_busy = false;
};
