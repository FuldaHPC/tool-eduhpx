#ifndef EDUHPX_RUN_FILE_H
#define EDUHPX_RUN_FILE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// One run file of EduHPX (CSV, format 1, see docs/run_file_format.md): one row per HPX message with the times of the
// HPX events and of the MPI send and receive. All times are microseconds since the epoch on the clock of the first node,
// -1 or an empty field = unknown.
//
// messages: one entry per row, as the timeline expects it. A field that is unknown is left out:
//   id, src, dst, size, group_kind, group, action,
//   hpx_create_us, hpx_done_us, tracy_send_us (HPX noticed the send request completed), tracy_recv_us (HPX has the parcel),
//   mpi_send_end_us, mpi_isend_us (length of the MPI_Isend call), mpi_send_done_us (send request completed, exact),
//   mpi_recv_end_us, mpi_irecv_us (the receive was posted this long before it completed), mpi_chunk_bytes (data message
//   of a large parcel)
class RunFile : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool loaded READ loaded NOTIFY changed)
    Q_PROPERTY(QString name READ name NOTIFY changed)       // run=... of the header, else the file name
    Q_PROPERTY(QVariantMap meta READ meta NOTIFY changed)   // key=value pairs of the "#" lines
    Q_PROPERTY(QVariantList messages READ messages NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit RunFile(QObject *parent = nullptr);

    // Reads a run file (file: or qrc: URL). Returns false and sets error (with the line number) on failure.
    Q_INVOKABLE bool load(const QUrl &file);
    // Forgets the run: the viewer goes back to its start page.
    Q_INVOKABLE void unload();

    bool loaded() const { return m_loaded; }
    QString name() const { return m_name; }
    QVariantMap meta() const { return m_meta; }
    QVariantList messages() const { return m_messages; }
    QString error() const { return m_error; }

signals:
    void changed();

private:
    void fail(const QString &message);

    bool m_loaded = false;
    QString m_name;
    QVariantMap m_meta;
    QVariantList m_messages;
    QString m_error;
};

#endif // EDUHPX_RUN_FILE_H
