#include "run_file.h"

#include <QFile>
#include <QFileInfo>

#include <algorithm>

namespace {
constexpr int kFormatVersion = 1;

// One line of RFC 4180 CSV (fields with commas or quotes are in double quotes, "" is a quote). The action names of
// HPX can contain commas.
bool splitLine(const QString &line, QStringList &out)
{
    out.clear();
    QString field;
    bool quoted = false;
    for (int i = 0; i < line.size(); ++i) {
        const QChar c = line.at(i);
        if (quoted) {
            if (c == QLatin1Char('"')) {
                if (i + 1 < line.size() && line.at(i + 1) == QLatin1Char('"')) {
                    field += c;
                    ++i;
                } else {
                    quoted = false;
                }
            } else {
                field += c;
            }
        } else if (c == QLatin1Char('"')) {
            quoted = true;
        } else if (c == QLatin1Char(',')) {
            out << field;
            field.clear();
        } else {
            field += c;
        }
    }
    out << field;
    return !quoted;
}

} // namespace

RunFile::RunFile(QObject *parent) : QObject(parent) {}

void RunFile::fail(const QString &message)
{
    m_loaded = false;
    m_messages.clear();
    m_meta.clear();
    m_name.clear();
    m_error = message;
    emit changed();
}

bool RunFile::load(const QUrl &url)
{
    QString path;
    if (url.scheme() == QLatin1String("qrc"))
        path = QLatin1Char(':') + url.path();
    else
        path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    const QString shown = QFileInfo(path).fileName();
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return fail(tr("Cannot open %1").arg(shown)), false;

    QVariantMap meta;
    bool versionSeen = false;
    bool headerSeen = false;
    // column positions of the fields we know; unknown columns are ignored, optional ones may be missing
    enum { Msg, Src, Dst, Size, GroupKind, Group, Action, Chunk, HpxCreate, MpiSendStart, MpiSendEnd, MpiSendDone,
           MpiRecvStart, MpiRecvEnd, HpxSendEvent, HpxRecv, HpxDone, ColumnCount };
    static const char *const names[ColumnCount] = {"msg", "src", "dst", "size", "group_kind", "group", "action", "chunk",
        "hpx_create", "mpi_send_start", "mpi_send_end", "mpi_send_done", "mpi_recv_start", "mpi_recv_end",
        "hpx_send_event", "hpx_recv", "hpx_done"};
    int col[ColumnCount];
    std::fill(col, col + ColumnCount, -1);

    QVariantList messages;
    QStringList fields;
    int lineNo = 0;
    while (!f.atEnd()) {
        ++lineNo;
        const QString line = QString::fromUtf8(f.readLine()).trimmed();
        if (line.isEmpty())
            continue;
        if (line.startsWith(QLatin1Char('#'))) {
            const QString text = line.mid(1).trimmed();
            if (text.startsWith(QLatin1String("eduhpx_run_csv"))) {
                bool ok = false;
                const int version = text.mid(14).trimmed().toInt(&ok);
                if (!ok)
                    return fail(tr("%1, line %2: the format version is missing").arg(shown).arg(lineNo)), false;
                if (version != kFormatVersion)
                    return fail(tr("%1: format version %2 is not supported (this EduHPX reads version %3)")
                                    .arg(shown).arg(version).arg(kFormatVersion)), false;
                versionSeen = true;
            } else {
                for (const QString &part : text.split(QLatin1Char(' '), Qt::SkipEmptyParts)) {
                    const int eq = part.indexOf(QLatin1Char('='));
                    if (eq > 0)
                        meta.insert(part.left(eq), part.mid(eq + 1));
                }
            }
            continue;
        }
        if (!versionSeen)
            return fail(tr("%1 is not an EduHPX run file (it must start with \"# eduhpx_run_csv 1\")").arg(shown)), false;
        if (!splitLine(line, fields))
            return fail(tr("%1, line %2: a quote is not closed").arg(shown).arg(lineNo)), false;

        if (!headerSeen) {
            for (int i = 0; i < ColumnCount; ++i)
                col[i] = fields.indexOf(QLatin1String(names[i]));
            for (int required : {Src, Dst, Size})
                if (col[required] < 0)
                    return fail(tr("%1, line %2: the column \"%3\" is missing").arg(shown).arg(lineNo).arg(names[required])), false;
            headerSeen = true;
            continue;
        }

        auto text = [&](int c) { return col[c] >= 0 && col[c] < fields.size() ? fields.at(col[c]) : QString(); };
        // -1 or empty = unknown
        auto number = [&](int c, bool &known) {
            const QString s = text(c).trimmed();
            bool ok = true;
            const double v = s.isEmpty() ? -1.0 : s.toDouble(&ok);
            if (!ok) {
                known = false;
                return -2.0;
            }
            known = v >= 0;
            return v;
        };

        bool known = false;
        QVariantMap m;
        for (int c : {Src, Dst, Size}) {
            const double v = number(c, known);
            if (!known)
                return fail(tr("%1, line %2: \"%3\" is not a number").arg(shown).arg(lineNo).arg(names[c])), false;
            m.insert(names[c], v);
        }
        m.insert(QStringLiteral("id"), text(Msg));
        m.insert(QStringLiteral("action"), text(Action));
        const QString kind = text(GroupKind).trimmed();
        m.insert(QStringLiteral("group_kind"), kind.isEmpty() ? QStringLiteral("burst") : kind);
        const double group = number(Group, known);
        m.insert(QStringLiteral("group"), known ? int(group) : 1);

        double t[ColumnCount];
        bool has[ColumnCount];
        for (int c : {HpxCreate, MpiSendStart, MpiSendEnd, MpiSendDone, MpiRecvStart, MpiRecvEnd, HpxSendEvent, HpxRecv, HpxDone}) {
            t[c] = number(c, has[c]);
            if (t[c] == -2.0)
                return fail(tr("%1, line %2: \"%3\" is not a number").arg(shown).arg(lineNo).arg(names[c])), false;
        }
        auto put = [&](const char *key, int c) { if (has[c]) m.insert(QLatin1String(key), t[c]); };
        put("hpx_create_us", HpxCreate);
        put("hpx_done_us", HpxDone);
        put("tracy_send_us", HpxSendEvent);
        put("tracy_recv_us", HpxRecv);
        put("mpi_send_end_us", MpiSendEnd);
        put("mpi_send_done_us", MpiSendDone);
        put("mpi_recv_end_us", MpiRecvEnd);
        if (has[MpiSendEnd] && has[MpiSendStart] && t[MpiSendEnd] >= t[MpiSendStart])
            m.insert(QStringLiteral("mpi_isend_us"), t[MpiSendEnd] - t[MpiSendStart]);
        if (has[MpiRecvEnd] && has[MpiRecvStart] && t[MpiRecvEnd] > t[MpiRecvStart])
            m.insert(QStringLiteral("mpi_irecv_us"), t[MpiRecvEnd] - t[MpiRecvStart]);
        const double chunk = number(Chunk, known);
        if (known && chunk > 0)
            m.insert(QStringLiteral("mpi_chunk_bytes"), chunk);
        messages.append(m);
    }

    if (!versionSeen)
        return fail(tr("%1 is not an EduHPX run file (it must start with \"# eduhpx_run_csv 1\")").arg(shown)), false;
    if (!headerSeen)
        return fail(tr("%1 has no column header").arg(shown)), false;
    if (messages.isEmpty())
        return fail(tr("%1 contains no messages").arg(shown)), false;

    m_meta = meta;
    m_name = meta.value(QStringLiteral("run")).toString();
    if (m_name.isEmpty())
        m_name = QFileInfo(path).completeBaseName();
    m_messages = messages;
    m_error.clear();
    m_loaded = true;
    emit changed();
    return true;
}
