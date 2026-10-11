#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QVariantMap>

#include <clocale>

int main(int argc, char* argv[])
{
    // mpv render API отдаёт кадры через OpenGL, поэтому сцена Qt Quick
    // тоже должна работать на OpenGL (по умолчанию на Windows — Direct3D 11).
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);

    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("WPlayer"));
    QGuiApplication::setApplicationName(QStringLiteral("WPlayer"));
    QGuiApplication::setApplicationVersion(QStringLiteral(WPLAYER_VERSION));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/qt/qml/WPlayer/icons/app.png")));

    // Inter — тот же шрифт, что в Bloom (400 и 500, как --fw-bold; 700 — только для «W»)
    QFontDatabase::addApplicationFont(QStringLiteral(":/qt/qml/WPlayer/fonts/Inter-Regular.ttf"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/qt/qml/WPlayer/fonts/Inter-Medium.ttf"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/qt/qml/WPlayer/fonts/Inter-Bold.ttf"));  // значок «W»
    QFont uiFont(QStringList{QStringLiteral("Inter"), QStringLiteral("Segoe UI")});
    uiFont.setPixelSize(13);
    uiFont.setHintingPreference(QFont::PreferNoHinting);
    QGuiApplication::setFont(uiFont);

    // libmpv требует, чтобы LC_NUMERIC был "C" (иначе ломается парсинг чисел)
    std::setlocale(LC_NUMERIC, "C");

    QQuickStyle::setStyle(QStringLiteral("Material"));

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(EXIT_FAILURE); }, Qt::QueuedConnection);

    // Файл/ссылка из командной строки ("Открыть с помощью" в проводнике) и опции
    // с именами как у mpv — WPlayer можно запускать вместо mpv из других программ
    // (например, из расширения браузера, которое передаёт Referer страницы):
    //   WPlayer.exe [--referrer=URL] [--user-agent=UA] [--force-media-title=T] [--start=СЕК] [--] источник
    // Незнакомые опции пропускаем, после "--" всё — источник.
    static const QStringList sourceOptionNames{
        QStringLiteral("referrer"), QStringLiteral("user-agent"), QStringLiteral("force-media-title")};
    QString startupFile;
    QVariantMap startupOptions;
    double startupStart = 0;
    bool optionsEnded = false;
    for (const QString& arg : QCoreApplication::arguments().mid(1)) {
        if (!optionsEnded && arg == QLatin1String("--")) {
            optionsEnded = true;
        } else if (!optionsEnded && arg.startsWith(QLatin1String("--"))) {
            const qsizetype eq = arg.indexOf(QLatin1Char('='));
            const QString name = eq < 0 ? arg.mid(2) : arg.mid(2, eq - 2);
            const QString value = eq < 0 ? QString() : arg.mid(eq + 1);
            if (name == QLatin1String("start"))
                startupStart = value.toDouble();  // не число — 0, с начала
            else if (sourceOptionNames.contains(name))
                startupOptions.insert(name, value);
        } else if (startupFile.isEmpty()) {
            startupFile = arg;
        }
    }
    engine.setInitialProperties({
        {QStringLiteral("startupFile"), startupFile},
        {QStringLiteral("startupOptions"), startupOptions},
        {QStringLiteral("startupStart"), startupStart},
    });

    engine.loadFromModule("WPlayer", "Main");
    return QGuiApplication::exec();
}
