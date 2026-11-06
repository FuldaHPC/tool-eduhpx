#include <QCommandLineParser>
#include <QEventLoop>
#include <QGuiApplication>
#include <QIcon>
#include <QImage>
#include <QMouseEvent>
#include <QWheelEvent>
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
        if (qEnvironmentVariable("EDUHPX_SCROLL") == QLatin1String("wheel")) {   // test: real wheel and mouse events down to the end
            const QPointF pos(window->width() / 2.0, window->height() / 2.0 + 60);
            double before = -1;
            for (int i = 0; i < 70; ++i) {
                QMouseEvent move(QEvent::MouseMove, pos + QPointF(i % 5, 0), window->mapToGlobal(pos.toPoint()), Qt::NoButton, Qt::NoButton, Qt::NoModifier);
                QCoreApplication::sendEvent(window, &move);
                QWheelEvent w(pos, window->mapToGlobal(pos.toPoint()), QPoint(), QPoint(0, -120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
                QCoreApplication::sendEvent(window, &w);
                wait(40);
                const double y = root->property("scrollY").toDouble();
                std::printf("WHEEL %d scrollY=%.1f contentH=%.1f%s\n", i, y, root->property("contentH").toDouble(), y < before ? "  <-- JUMP BACK" : "");
                before = y;
            }
        }
        if (qEnvironmentVariable("EDUHPX_SCROLL") == QLatin1String("1")) {       // test: scroll to the end and see whether it stays there
            QMetaObject::invokeMethod(root, "scrollBy", Q_ARG(QVariant, 1e7), Q_ARG(QVariant, 0));
            for (int i = 0; i < 4; ++i) {
                wait(300);
                std::printf("SCROLL step %d scrollY=%f contentH=%f\n", i, root->property("scrollY").toDouble(), root->property("contentH").toDouble());
            }
        }
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
        if (!qEnvironmentVariable("EDUHPX_REOPEN").isEmpty()) {     // test: open a second file while a late group is selected
            QMetaObject::invokeMethod(root, "select", Q_ARG(QVariant, 30));
            const QString other = qEnvironmentVariable("EDUHPX_REOPEN");
            QMetaObject::invokeMethod(root, "openFile", Q_ARG(QVariant, QUrl::fromLocalFile(QDir::current().absoluteFilePath(other))));
            wait(500);
        }
        if (qEnvironmentVariable("EDUHPX_PATH_REPORT") == QLatin1String("1")) {
            QVariant report;
            QMetaObject::invokeMethod(root, "pathReport", Q_RETURN_ARG(QVariant, report));
            std::printf("PATHREPORT %s\n", qPrintable(report.toString()));
        }
        if (qEnvironmentVariable("EDUHPX_START_PAGE") == QLatin1String("1"))
            QMetaObject::invokeMethod(root, "showStartPage");   // test: back to the start page after a run was loaded
        if (qEnvironmentVariable("EDUHPX_CRITICAL") == QLatin1String("1"))
            root->setProperty("criticalOn", true);    // preview with the critical path button on
        if (!qEnvironmentVariable("EDUHPX_ARROWS").isEmpty())
            root->setProperty("arrowFilter", qEnvironmentVariable("EDUHPX_ARROWS"));   // preview with the Data / Requests filter
        // the views are named after the positional arguments that follow the file
        QStringList specs = args.mid(1);
        wait(500);
        return render(window, root, parser.value(renderOption), specs) == 0 ? 0 : 2;
    }
    return app.exec();
}
