#include "YtDlp.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QProcessEnvironment>
#include <QUrl>

namespace {

const char* const kDownloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe";

// Расширения, которые mpv может открыть сам, без yt-dlp
const QStringList kMediaSuffixes = {
    QStringLiteral("mka"), QStringLiteral("m4a"), QStringLiteral("aac"),  QStringLiteral("mp3"),
    QStringLiteral("opus"), QStringLiteral("ogg"), QStringLiteral("oga"), QStringLiteral("flac"),
    QStringLiteral("wav"), QStringLiteral("ac3"), QStringLiteral("eac3"), QStringLiteral("dts"),
    QStringLiteral("mkv"), QStringLiteral("mp4"), QStringLiteral("webm"), QStringLiteral("mov"),
    QStringLiteral("ts"),  QStringLiteral("m3u8"), QStringLiteral("mpd"),
};

QString lastLine(const QString& text)
{
    const QStringList lines = text.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    return lines.isEmpty() ? QString() : lines.last().trimmed();
}

} // namespace

YtDlp::YtDlp(QObject* parent) : QObject(parent), m_network(new QNetworkAccessManager(this))
{
    refreshVersion();
}

QString YtDlp::bundledPath() const
{
    return QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("yt-dlp.exe"));
}

bool YtDlp::bundled() const
{
    return QFileInfo::exists(bundledPath());
}

QString YtDlp::program() const
{
    // Своя копия рядом с exe, иначе ищем в PATH
    return bundled() ? bundledPath() : QStringLiteral("yt-dlp");
}

QProcess* YtDlp::makeProcess()
{
    auto* process = new QProcess(this);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("PYTHONIOENCODING"), QStringLiteral("utf-8"));
    env.insert(QStringLiteral("PYTHONUTF8"), QStringLiteral("1"));
    process->setProcessEnvironment(env);
    return process;
}

void YtDlp::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

bool YtDlp::isDirectMedia(const QString& source) const
{
    QString s = source.trimmed();
    if (s.startsWith(QLatin1Char('"')))
        s.remove(QLatin1Char('"'));
    const QUrl url(s);
    const QString scheme = url.scheme().toLower();
    if (scheme != QLatin1String("http") && scheme != QLatin1String("https"))
        return true;  // локальный файл, file://, или протокол, который mpv понимает сам
    return isMediaUrl(url);
}

bool YtDlp::isMediaUrl(const QUrl& url)
{
    const QString scheme = url.scheme().toLower();
    return (scheme == QLatin1String("http") || scheme == QLatin1String("https"))
           && kMediaSuffixes.contains(QFileInfo(url.path()).suffix().toLower());
}

// ---------------------------------------------------------------------------
// Разрешение ссылки на аудио
// ---------------------------------------------------------------------------

void YtDlp::resolveAudio(const QString& url)
{
    cancelResolve();

    QProcess* process = makeProcess();
    m_resolveProcess = process;
    emit resolvingChanged();

    auto finish = [this, process] {
        process->deleteLater();
        if (m_resolveProcess == process) {
            m_resolveProcess = nullptr;
            emit resolvingChanged();
        }
    };

    connect(process, &QProcess::finished, this,
            [this, process, url, finish](int exitCode, QProcess::ExitStatus status) {
                const QString out = QString::fromUtf8(process->readAllStandardOutput());
                const QString err = QString::fromUtf8(process->readAllStandardError());
                finish();

                const QString direct = out.section(QLatin1Char('\n'), 0, 0).trimmed();
                if (status == QProcess::NormalExit && exitCode == 0 && !direct.isEmpty()) {
                    emit audioResolved(url, direct);
                } else {
                    const QString reason = lastLine(err);
                    emit resolveFailed(reason.isEmpty() ? tr("yt-dlp завершился с кодом %1").arg(exitCode) : reason);
                }
            });

    connect(process, &QProcess::errorOccurred, this, [this, finish](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;  // остальные ошибки придут через finished
        finish();
        emit resolveFailed(tr("yt-dlp не найден. Скачайте его в настройках."));
    });

    process->start(program(), {
        QStringLiteral("--no-playlist"),
        QStringLiteral("--no-warnings"),
        QStringLiteral("-f"), QStringLiteral("bestaudio/best"),
        QStringLiteral("-g"),
        url,
    });
}

void YtDlp::cancelResolve()
{
    if (!m_resolveProcess)
        return;
    QProcess* process = m_resolveProcess;
    m_resolveProcess = nullptr;
    process->disconnect(this);
    process->kill();
    process->deleteLater();
    emit resolvingChanged();
}

// ---------------------------------------------------------------------------
// Версия и обновление
// ---------------------------------------------------------------------------

void YtDlp::refreshVersion()
{
    QProcess* process = makeProcess();
    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus) {
        const QString v = exitCode == 0 ? QString::fromUtf8(process->readAllStandardOutput()).trimmed() : QString();
        process->deleteLater();
        m_version = v;
        emit versionChanged();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_version.clear();
        emit versionChanged();
    });
    process->start(program(), {QStringLiteral("--version")});
}

void YtDlp::update()
{
    if (m_busy)
        return;
    if (!bundled()) {
        download();
        return;
    }

    setBusy(true);
    QProcess* process = makeProcess();
    process->setProcessChannelMode(QProcess::MergedChannels);

    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus status) {
        const QString out = QString::fromUtf8(process->readAll());
        process->deleteLater();
        setBusy(false);
        refreshVersion();
        const bool ok = status == QProcess::NormalExit && exitCode == 0;
        emit updateFinished(ok, lastLine(out));
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        setBusy(false);
        emit updateFinished(false, tr("Не удалось запустить yt-dlp"));
    });

    process->start(bundledPath(), {QStringLiteral("-U")});
}

void YtDlp::download()
{
    setBusy(true);

    QNetworkRequest request{QUrl(QString::fromLatin1(kDownloadUrl))};
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply* reply = m_network->get(request);

    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        setBusy(false);

        if (reply->error() != QNetworkReply::NoError) {
            emit updateFinished(false, tr("Ошибка загрузки: %1").arg(reply->errorString()));
            return;
        }

        const QString target = bundledPath();
        const QString partial = target + QStringLiteral(".part");
        QFile file(partial);
        if (!file.open(QIODevice::WriteOnly) || file.write(reply->readAll()) < 0) {
            emit updateFinished(false, tr("Не удалось записать %1").arg(QDir::toNativeSeparators(partial)));
            return;
        }
        file.close();

        QFile::remove(target);
        if (!QFile::rename(partial, target)) {
            emit updateFinished(false, tr("Не удалось сохранить %1").arg(QDir::toNativeSeparators(target)));
            return;
        }

        refreshVersion();
        emit updateFinished(true, tr("yt-dlp скачан"));
    });
}
