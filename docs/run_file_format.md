# EduHPX run file, format 1

A text file, UTF-8, one row per HPX message. Lines that start with `#` are metadata, the first line must be
`# eduhpx_run_csv 1`. The other `#` lines hold `key=value` pairs separated by blanks (`run`, `localities`, `nodes`, `program`,
`grouping`, ...; unknown keys are ignored; `run` is shown in the title). The first line that is not a comment is the column header.
Fields are separated by commas; a field with a comma or a quote is in double quotes (`""` is a quote), as in RFC 4180.
Columns are found by name, their order does not matter, unknown columns are ignored.

| column | meaning |
|---|---|
| `msg` | id of the parcel (text) |
| `src`, `dst`, `size` | sending and receiving locality, size of the HPX message in bytes (required) |
| `group_kind`, `group` | `broadcast`, `barrier`, `burst` ...; number inside the kind (1, 2, ...). Empty: `burst`, 1 |
| `action` | name of the HPX action |
| `chunk` | `0`, or the size in bytes of the MPI message that carries the data of a large (zero-copy) parcel |
| `hpx_create` | HPX created the parcel |
| `mpi_send_start`, `mpi_send_end` | start and end of the `MPI_Isend` call |
| `mpi_send_done` | the send request completed (exact, from the measuring MPI) |
| `mpi_recv_start` | the matching `MPI_Irecv` was posted |
| `mpi_recv_end` | the receive completed (the message arrived) |
| `hpx_send_event` | HPX noticed the send has completed |
| `hpx_recv` | HPX has the parcel (receive event) |
| `hpx_done` | the action finished |

All times: microseconds since the epoch on the clock of the first node (nodes already corrected: the offsets of the ping-pong refined with the fastest MPI messages of each pair of nodes), `-1` or empty = unknown.
A message without `mpi_send_end` or `mpi_recv_end` is counted but not drawn.
