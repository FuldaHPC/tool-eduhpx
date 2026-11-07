# Installing HPX for EduHPX

EduHPX shows what HPX and MPI do for every message. For that it needs

1. the **measuring MPI** (branch `eduhpx_mpi_data` of the EduMPI repository, as a source tarball, see [mpi_tarball.md](mpi_tarball.md); the tarball is built and tested but not published yet) and
2. **HPX with the parcel log**, which is built by `scripts/install-hpx.sh` from this repository.

HPX itself is not part of this repository. The script downloads one fixed HPX commit from GitHub, checks the checksum of the
download, applies `patches/hpx-ec3b59b1.patch` and builds HPX against the measuring MPI.

## Install

```
scripts/install-hpx.sh --mpi-prefix ~/eduhpx_mpi --prefix ~/eduhpx_hpx --jobs 16
```

| option | meaning |
|---|---|
| `--mpi-prefix DIR` | install directory of the measuring MPI. Default: `$EDUHPX_MPI_PREFIX`, else `~/eduhpx_mpi` if it exists |
| `--prefix DIR` | where HPX is installed (default `~/eduhpx_hpx`) |
| `--jobs N` | parallel build jobs (default: all cores) |
| `--build-dir DIR` | build directory (default: a new temporary directory). Use a local disk; on a cluster the home directory is often a slow network file system |
| `--download-dir DIR` | where the HPX tarball is kept (default `~/.cache/eduhpx`) |
| `--source-dir DIR` | use an unpacked HPX source at the pinned commit instead of downloading |
| `--hwloc-root DIR` | hwloc to use (default: the one in the MPI prefix, else the system's) |
| `--keep-build` | keep the build directory (with `configure.log`, `build.log`) |

Needs: cmake 3.18 or newer, the C++ compiler behind the MPI wrappers (HPX and MPI must use the same one), make or ninja,
curl or wget, tar, patch or git, and internet access (HPX fetches Boost 1.86, asio and Tracy sources while it configures).
The build took 29 minutes with 32 jobs on a 32-core node (measured on our cluster); with fewer cores expect a multiple of that. It works on Linux and macOS.

At the end the script checks that the installed HPX contains the parcel log, writes `share/eduhpx/hpx-build-info.txt` and
prints how to use the installation.

## What the patch does

The patch adds a **parcel log**: a list of events of every HPX parcel with a wall-clock time stamp, written to files.
Nothing is attached or connected while the program runs.

HPX is configured with `HPX_WITH_TRACY=ON` and `HPX_WITH_PARCEL_PROFILING=ON`. This is only the compile switch that
activates the parcel hooks in HPX; the Tracy profiler is never started or connected (a connected Tracy capture slows an HPX
program down by a factor of 10 to 25).

Environment variables:

| variable | meaning |
|---|---|
| `HPX_PARCEL_LOG=<prefix>` | switch the log on. Process `r` writes `<prefix>.loc<r>.csv` (`r` = `OMPI_COMM_WORLD_RANK` or `PMIX_RANK`, else 0) |
| `HPX_PARCEL_LOG_MAX_MB=<n>` | size cap of the file of one process (default 2048). Further events are dropped and a warning is printed at exit |

Without `HPX_PARCEL_LOG` the log costs one test per hook. Events are collected in memory and appended to the file in blocks of
8192 events.

File format (one event per line, times in microseconds since the epoch, `<id>` = `<msb>:<lsb>` of the parcel id in hex):

```
C,<id>,<action name>,<creating thread>,<time>   the parcel was handed to the send path
S,<id>,<size>,<to locality>,<time>              the parcel was sent
R,<id>,<from locality>,<time>                   the parcel arrived (header decoded)
P,<id>,<from locality>,<time>,<parent thread>   the action was put on the scheduler
D,<id>,<time>                                   scheduling of the action returned
```

`eduhpx-merge` joins these files with the MPI log into the run file.

## Update to a newer HPX

The patch touches four files: `libs/core/tracing/src/backends/tracy.cpp`,
`libs/core/tracing/include/hpx/tracing/backends/tracy.hpp`, `libs/full/parcelset/src/parcel.cpp` and
`libs/full/parcelset/src/parcelhandler.cpp`. To move to a newer commit: check out that commit, apply the old patch (with `patch -p1`;
fix rejected hunks by hand), write the new patch with `diff -u`, and set `HPX_COMMIT` and `HPX_TARBALL_SHA256` in
`scripts/install-hpx.sh`. Then run the broadcast test and compare the event counts with the old version.

## Licence

HPX is published under the Boost Software License 1.0. The patch contains lines of HPX files and stays under that licence; the
HPX copyright notices in the patched files are kept.
