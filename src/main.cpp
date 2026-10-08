#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>

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

    // Файл/ссылка из командной строки ("Открыть с помощью" в проводнике)
    const QStringList args = QCoreApplication::arguments();
    engine.setInitialProperties({{QStringLiteral("startupFile"), args.value(1)}});

    engine.loadFromModule("WPlayer", "Main");
    return QGuiApplication::exec();
}
