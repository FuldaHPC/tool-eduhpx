<p align="center"><img src="gui/assets/logo.png" alt="EduHPX" width="260"></p>

# EduHPX

EduHPX shows what happens inside an [HPX](https://github.com/STEllAR-GROUP/hpx) program and in the MPI messages below it,
on **one timeline**: when HPX prepares a parcel, when MPI sends and receives it, when HPX picks it up and runs the action.
Collectives (broadcast ...) are grouped, drawn as a tree and analysed along their critical path.

<p align="center"><img src="screenshots/flat_broadcast_by_locality.png" alt="One flat broadcast, by locality" width="900"></p>

*One broadcast of 16 localities on 4 nodes: green = MPI send, red = MPI receive, blue frame = time in MPI, the rest is HPX.*

<p align="center"><img src="screenshots/3d_tree_send_recv_ratio.png" alt="A broadcast as a tree in 3D, with the nodes of the cluster" width="900"></p>

*New in 0.0.3, the tree in 3D: every node of the cluster is a glass cube with its localities inside (the first node bottom left), green lines are sends, red lines are receives (each can be switched off), and the colour of a locality shows whether it sent or received more, who sent or received the most, or when the data arrived. Click a cube to look at it. Gold = critical path.*

## Why EduHPX?

EduHPX is the little brother of **EduMPI Suite**: [EduMPI](https://github.com/AnnaLena77/EduMPI) (an Open MPI that records
MPI communication), EduStore (its database, a folder in the EduMPI repo) and the
[EduMPI GUI](https://github.com/AnnaLena77/EduMPI_GUI).

In [HPX](https://github.com/STEllAR-GROUP/hpx) you do not write sends and receives: HPX packs a remote call into a *parcel* and
sends it for you, over TCP, LCI or MPI. That is convenient, but when a program gets slow, it is hard to say whether the time is
lost in HPX (waiting, scheduling, preparing the parcel) or in the transport below it (the MPI send, the receive).

[HPX's Tracy integration](https://v4xsh.dev/blog/gsoc-2026-hpx-tracy/) (Google Summer of Code 2026) shows tasks, threads and the parcels of each locality, but not the MPI messages below them. EduMPI shows the MPI messages,
but knows nothing about parcels. **EduHPX puts both on one timeline**: for every parcel you see what HPX did and what MPI did.

## Download

Ready-made viewer (version 0.0.3), built by the workflows on the branch `deploy`:

| System | File |
|---|---|
| Linux | [`EduHPX_0.0.3-x86_64.AppImage`](https://github.com/FuldaHPC/tool-eduhpx/releases/download/v0.0.3/EduHPX_0.0.3-x86_64.AppImage): make it executable (`chmod +x`), then start it |
| macOS | [`EduHPX_0.0.3.dmg`](https://github.com/FuldaHPC/tool-eduhpx/releases/download/v0.0.3/EduHPX_0.0.3.dmg): the app is not signed, see the note below |
| Windows | [`EduHPX_0.0.3-windows.zip`](https://github.com/FuldaHPC/tool-eduhpx/releases/download/v0.0.3/EduHPX_0.0.3-windows.zip): unpack, start `eduhpx.exe` |
| Example run files | [`EduHPX_0.0.3_examples.zip`](https://github.com/FuldaHPC/tool-eduhpx/releases/download/v0.0.3/EduHPX_0.0.3_examples.zip), also built into the app: *File > Examples* |
| Measuring MPI (source) | [`eduhpx_mpi_data-5.0.11rc1-eduhpx1.tar.gz`](https://github.com/FuldaHPC/tool-eduhpx/releases/download/v0.0.3/eduhpx_mpi_data-5.0.11rc1-eduhpx1.tar.gz) and its [`.sha256`](https://github.com/FuldaHPC/tool-eduhpx/releases/download/v0.0.3/eduhpx_mpi_data-5.0.11rc1-eduhpx1.tar.gz.sha256): Open MPI 5.0.11rc1 with the EduMPI hooks, to trace your own program. `scripts/install-mpi.sh` downloads and builds it for you |

All releases: <https://github.com/FuldaHPC/tool-eduhpx/releases>. What changed: [release notes of 0.0.3](docs/release-notes/0.0.3.md). The three viewer downloads also contain the examples.

**macOS: the first start.** The app is not signed with an Apple certificate, so macOS blocks it once (it is not damaged):

- macOS 14 and older: right click on `EduHPX.app` > *Open* > *Open*.
- macOS 15 and newer: double click the app once (it is blocked), then *System Settings > Privacy & Security*, scroll down
  to the message about EduHPX and click *Open Anyway*.
- Or in the Terminal: `xattr -dr com.apple.quarantine /Applications/EduHPX.app`.

Copy `EduHPX.app` from the dmg to *Applications* first. This is needed only once.

## The parts

| Folder | What it is |
|---|---|
| [`gui/`](gui/) | The viewer (Qt 6). Opens a run file and shows the timeline. Runs on macOS, Linux and Windows. [Details and a tour of the window](gui/README.md) |
| [`scripts/`](scripts/) | `install-mpi.sh` (measuring MPI), `install-hpx.sh` (patched HPX), `eduhpx-run` (run a program, get `run.csv`) and `eduhpx-merge`. Tested on a Linux cluster with Slurm. [What works and what is missing](scripts/README.md) |
| [`examples/`](examples/) | Ready-made run files to try the viewer |
| [`sample-app/`](sample-app/) | A small HPX program (one collective, flat or hierarchical) to try the whole chain; the examples were made with it |
| [`docs/`](docs/) | **[Trace an HPX program: install, run, look at the result](docs/tracing_guide.md)**, format of the run file and of the raw MPI log, HPX install notes, the measuring MPI as a tarball |

## Quick start

1. **Try it:** download the viewer (see above) and start it: the start screen lists the built-in examples, every HPX collective
   flat and as a tree on 16 to 64 localities. Or open a file from `examples/`.
2. **Measure your own program** (Linux, tested on a cluster with Slurm and Open MPI; the complete description with all options,
   a Slurm script and troubleshooting is the **[tracing guide](docs/tracing_guide.md)**):
   1. Measuring MPI, from the tarball of the release: `scripts/install-mpi.sh --prefix ~/eduhpx_mpi` ([how it is built and updated](docs/mpi_tarball.md)).
   2. Patched HPX: `scripts/install-hpx.sh --mpi-prefix ~/eduhpx_mpi --prefix ~/eduhpx_hpx` ([details](docs/install.md)).
   3. Build your program against that HPX (the sample in [`sample-app/`](sample-app/) shows how).
   4. Run: `scripts/eduhpx-run --mpi ~/eduhpx_mpi --hpx ~/eduhpx_hpx --out my_run -- mpirun -np 16 ./app ...`, then open
      `my_run/run.csv` with EduHPX ([details](scripts/README.md)).

**Status (2026-11-08):** the viewer is released (0.0.3). The whole chain from a program to `run.csv` was tested on one
cluster (4 nodes, 16 localities, all HPX collectives, flat and hierarchical); macOS as a measuring system and runs without Slurm
are not tested yet.

## Screenshots

| Hierarchical broadcast | Tree of the broadcast |
|---|---|
| <img src="screenshots/hierarchical_broadcast_by_locality.png" width="440"> | <img src="screenshots/hierarchical_broadcast_tree.png" width="440"> |
| **3D tree: who sent the most (64 localities on 8 nodes)** | **3D tree: look at one locality** |
| <img src="screenshots/3d_tree_max_send_64_localities.png" width="440"> | <img src="screenshots/3d_tree_focus_on_locality.png" width="440"> |

## Licence

BSD-3-Clause, see [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
EduHPX is part of the Edu* tools for visualising parallel programs, like EduMPI.
