<p align="center"><img src="gui/assets/logo.png" alt="EduHPX" width="260"></p>

# EduHPX

EduHPX shows what happens inside an [HPX](https://github.com/STEllAR-GROUP/hpx) program and in the MPI messages below it,
on **one timeline**: when HPX prepares a parcel, when MPI sends and receives it, when HPX picks it up and runs the action.
Collectives (broadcast ...) are grouped, drawn as a tree and analysed along their critical path.

<p align="center"><img src="screenshots/flat_broadcast_by_locality.png" alt="One flat broadcast, by locality" width="900"></p>

*One broadcast of 16 localities on 4 nodes: green = MPI send, red = MPI receive, blue frame = time in MPI, the rest is HPX.*

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
