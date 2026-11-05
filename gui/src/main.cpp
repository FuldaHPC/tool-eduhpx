#include <QCommandLineParser>
#include <QEventLoop>
#include <QGuiApplication>
#include <QIcon>
#include <QImage>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QDir>
#include <QUrl>

#include <cstdio>

namespace {
// Waits while the event loop paints (the canvases of the timeline paint asynchronously).
void wait(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

// Headless preview: eduhpx run.csv --render out_dir kind:k:view ...   (QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software)
// writes one PNG per "kind:k:view", e.g. broadcast:3:tree burst:9:locality (view: locality | message | tree).
int render(QQuickWindow *window, QObject *root, const QString &dir, const QStringList &specs)
{
    QDir().mkpath(dir);
    int failed = 0;
    for (const QString &spec : specs) {
        const QStringList part = spec.split(QLatin1Char(':'));
        if (part.size() != 3) {
            std::fprintf(stderr, "bad spec %s (kind:k:view)\n", qPrintable(spec));
            ++failed;
            continue;
        }
        QMetaObject::invokeMethod(root, "showView", Q_ARG(QVariant, part[2]));
        QMetaObject::invokeMethod(root, "showGroup", Q_ARG(QVariant, part[0]), Q_ARG(QVariant, part[1].toInt()));
        wait(600);
        const QString file = QDir(dir).filePath(part[0] + part[1] + QLatin1Char('_') + part[2] + QLatin1String(".png"));
        const QImage image = window->grabWindow();
        if (image.isNull() || !image.save(file)) {
            std::fprintf(stderr, "%s: MISSING\n", qPrintable(file));
            ++failed;
        } else {
            std::printf("%s ok\n", qPrintable(file));
        }
    }
    return failed;
}
} // namespace

int main(int argc, char *argv[])
{
    // the example list (examples/index.json) is read from the program's own resources with an XMLHttpRequest
    qputenv("QML_XHR_ALLOW_FILE_READ", "1");
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("EduHPX"));
    QGuiApplication::setApplicationVersion(QStringLiteral("0.0.1"));
    QGuiApplication::setOrganizationName(QStringLiteral("EduHPX"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/qt/qml/EduHPX/assets/icon_256.png")));
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("EduHPX: HPX parcels and MPI messages on one timeline"));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addPositionalArgument(QStringLiteral("run.csv"), QStringLiteral("run file to open"));
    QCommandLineOption renderOption(QStringLiteral("render"), QStringLiteral("write PNG files of the given views to <dir> and exit"), QStringLiteral("dir"));
    parser.addOption(renderOption);
    parser.process(app);

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); },
                     Qt::QueuedConnection);
    engine.loadFromModule("EduHPX", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    QObject *root = engine.rootObjects().first();

    const QStringList args = parser.positionalArguments();
    const bool rendering = parser.isSet(renderOption);
    if (!args.isEmpty()) {
        const QString file = args.first();
        const QUrl url = file.startsWith(QLatin1String("qrc:")) ? QUrl(file) : QUrl::fromLocalFile(QDir::current().absoluteFilePath(file));
        QMetaObject::invokeMethod(root, "openFile", Q_ARG(QVariant, url));
    }
    if (rendering) {
        auto *window = qobject_cast<QQuickWindow *>(root);
        if (qEnvironmentVariable("EDUHPX_CRITICAL") == QLatin1String("1"))
            root->setProperty("criticalOn", true);    // preview with the critical path button on
        // the views are named after the positional arguments that follow the file
        QStringList specs = args.mid(1);
        wait(500);
        return render(window, root, parser.value(renderOption), specs) == 0 ? 0 : 2;
    }
    return app.exec();
}
