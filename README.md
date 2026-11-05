<p align="center"><img src="gui/assets/logo.png" alt="EduHPX" width="260"></p>

# EduHPX

EduHPX shows what happens inside an [HPX](https://github.com/STEllAR-GROUP/hpx) program and in the MPI messages below it,
on **one timeline**: when HPX prepares a parcel, when MPI sends and receives it, when HPX picks it up and runs the action.
Collectives (broadcast ...) are grouped, drawn as a tree and analysed along their critical path.

<p align="center"><img src="screenshots/flat_broadcast_by_locality.png" alt="One flat broadcast, by locality" width="900"></p>

*One broadcast of 16 localities on 4 nodes: green = MPI send, red = MPI receive, blue frame = time in MPI, the rest is HPX.*

## Why EduHPX?

EduHPX is the little brother of **EduMPI Suite**: [EduMPI](https://github.com/AnnaLena77/EduMPI) (an Open MPI that records
MPI communication), EduStore (its database, a folder in the EduMPI repo) and the
[EduMPI GUI](https://github.com/AnnaLena77/EduMPI_GUI).

In [HPX](https://github.com/STEllAR-GROUP/hpx) you do not write sends and receives: HPX packs a remote call into a *parcel* and
sends it for you, over TCP, LCI or MPI. That is convenient, but when a program gets slow, it is hard to say whether the time is
lost in HPX (waiting, scheduling, preparing the parcel) or in the transport below it (the MPI send, the receive).

[HPX's Tracy integration](https://v4xsh.dev/blog/gsoc-2026-hpx-tracy/) (Google Summer of Code 2026) shows tasks and threads, but not (yet) the parcels between localities. EduMPI shows the MPI messages,
but knows nothing about parcels. **EduHPX puts both on one timeline**: for every parcel you see what HPX did and what MPI did.

## The parts

| Folder | What it is |
|---|---|
| [`gui/`](gui/) | The viewer (Qt 6). Opens a run file and shows the timeline. Runs on macOS, Linux and Windows. [Details and a tour of the window](gui/README.md) |
| [`scripts/`](scripts/) | Install a patched HPX and the measuring MPI, run a program and write the run file. Linux and macOS (on Windows: WSL2). *In progress.* |
| [`examples/`](examples/) | Ready-made run files to try the viewer |
| [`docs/`](docs/) | Format of the run file and of the raw MPI log, install notes |

## Quick start

1. **Try it:** build the viewer (see [gui/README.md](gui/README.md)), start it and choose *File > Examples*, or open a file from `examples/`.
2. **Measure your own program:** install the measuring MPI and the patched HPX, run your program with `eduhpx-run`,
   open the `run.csv` it writes. *(The scripts are not finished yet, see [scripts/](scripts/).)*

## Screenshots

| Hierarchical broadcast | Tree of the broadcast |
|---|---|
| <img src="screenshots/hierarchical_broadcast_by_locality.png" width="440"> | <img src="screenshots/hierarchical_broadcast_tree.png" width="440"> |

## Licence

BSD-3-Clause, see [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
EduHPX is part of the Edu* tools for visualising parallel programs, like EduMPI.
