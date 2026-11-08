# Trace an HPX program with EduHPX: install, run, look at the result

This guide takes you from nothing to a trace of your own HPX program: you install the **measuring MPI** and an **HPX with the parcel log**, build your program against them, run it with one command, and open the result in the **EduHPX viewer**.

```
your HPX program ──► HPX with the parcel log ──► measuring MPI (Open MPI + EduMPI hooks) ──► network
        │                      │                              │
        └── parcels.loc<N>.csv ┘                              └── eduhpx.mpi.<N>.bin
                          eduhpx-merge  ──►  run.csv  ──►  EduHPX viewer
```

What you get: every HPX *parcel* (the message HPX makes of a remote call) and the MPI messages that carry it, on one timeline. Collectives (broadcast, reduce, gather, all-to-all, ...) are grouped and shown as trees, also in 3D with the nodes of your cluster, with a critical path.

**What was tested.** The chain was tested on one Linux cluster (Slurm, Open MPI with UCX), with the sample program of this repository (16 localities on 4 nodes, flat and hierarchical collectives). Every command of this guide was run once more from the release files: the measuring MPI built by `install-mpi.sh` from the tarball, the sample built against the installed HPX, and `eduhpx-run` in a Slurm job on 2 nodes with 8 localities. The viewer runs on macOS, Linux and Windows; the measuring chain only on Linux. Other launchers than `mpirun`, other MPIs and macOS as a measuring system were not tested.

## 0. What you need

| | |
|---|---|
| A Linux machine or cluster | Several nodes with a shared file system are the interesting case; one node works too. Slurm is optional (with it, `eduhpx-run` measures the clock differences between the nodes for you). |
| Compiler and tools | A C compiler and a C++17 compiler, `make`, `cmake` 3.18 or newer, `python3`, `curl` or `wget`, `tar`, `patch` or `git`. UCX development files only if you want the UCX transport of Open MPI. |
| Internet | On the machine that builds HPX: HPX downloads Boost 1.86, asio and Tracy sources while it configures. |
| Time and disk | The measuring MPI: about 20 to 35 minutes with 16 cores. HPX: about 30 minutes with 32 cores. Build on a **local disk** (`/tmp`): on a cluster the home directory is often a slow network file system and the build takes many times longer. |
| The EduHPX repository | `git clone https://github.com/FuldaHPC/tool-eduhpx.git` (the scripts and the patch are in it). Below it is called `$EDUHPX`. |

```
git clone https://github.com/FuldaHPC/tool-eduhpx.git
export EDUHPX=$PWD/tool-eduhpx
```

## 1. Install the measuring MPI

The measuring MPI is Open MPI 5.0.11rc1 with the EduMPI instrumentation (branch `eduhpx_mpi_data` of the [EduMPI repository](https://github.com/AnnaLena77/EduMPI)): it records every send and receive in a binary file per rank (`eduhpx.mpi.<rank>.bin`), without a database and without an extra thread. It comes as a source tarball, attached to the EduHPX release, with its SHA-256 checksum.

```
$EDUHPX/scripts/install-mpi.sh --prefix $HOME/eduhpx_mpi --build-dir /tmp/eduhpx-mpi-build --jobs 16
```

The script downloads `eduhpx_mpi_data-5.0.11rc1-eduhpx1.tar.gz`, checks its checksum, builds it from the unpacked archive, installs it into `--prefix`, and runs a small test (4 ranks send and receive, the files of rank 0 are read back). At the end it prints the transports that were built (`ob1` always, `ucx` if UCX was found) and what to do next.

| option | meaning |
|---|---|
| `--prefix DIR` | where the MPI is installed (default `~/eduhpx_mpi`) |
| `--tarball FILE\|URL` | use a tarball you already have (default: the one of the release) |
| `--jobs N` | parallel build jobs (default: all cores) |
| `--build-dir DIR` | build directory; use a local disk |
| `--no-test`, `--keep-build` | skip the test; keep the build directory |

By hand (what the script does): `tar xzf eduhpx_mpi_data-5.0.11rc1-eduhpx1.tar.gz && cd eduhpx_mpi_data-5.0.11rc1-eduhpx1 && ./configure --prefix=$HOME/eduhpx_mpi --with-pmix=internal --with-hwloc=internal --with-prrte=internal && make -j 16 && make install`. More in [mpi_tarball.md](mpi_tarball.md).

Check: `$HOME/eduhpx_mpi/bin/mpirun --version` shows Open MPI 5.0.11rc1; the file `$HOME/eduhpx_mpi/share/eduhpx/mpi-build-info.txt` says which tarball it was built from.

## 2. Install HPX with the parcel log

EduHPX needs to know when HPX creates a parcel, sends it, receives it and runs the action. For that it uses a small patch of HPX (the *parcel log*). HPX is not part of this repository: the script downloads **one fixed HPX commit** (`ec3b59b`, HPX master of November 2026) from GitHub, checks the checksum, applies `patches/hpx-ec3b59b1.patch` and builds it against the measuring MPI.

```
$EDUHPX/scripts/install-hpx.sh --mpi-prefix $HOME/eduhpx_mpi --prefix $HOME/eduhpx_hpx \
    --build-dir /tmp/eduhpx-hpx-build --jobs 32
```

The log is off unless you switch it on with `HPX_PARCEL_LOG` (see section 5), so this HPX is also fine for normal runs; the cost of the log is described in the [README](../README.md#overhead). Nothing is attached or connected at run time: the Tracy profiler that HPX can use is only compiled in as a switch for the hooks and never started. Options and details: [install.md](install.md).

At the end the script checks that the installed HPX contains the parcel log, and prints how to build your program against it (the `HPX_DIR`) and which library path to use.

## 3. Build your program against it

Your program must be built with **this** HPX (and the compiler the MPI wrappers use), because the log is inside the HPX library. A normal HPX program does not change: the repository has a small sample, [`sample-app/`](../sample-app/), that runs one collective, flat or hierarchical, repeated; the examples of the viewer were made with it.

```
cd $EDUHPX/sample-app
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_COMPILER=$($HOME/eduhpx_mpi/bin/mpicxx --showme:command) \
      -DHPX_DIR=$HOME/eduhpx_hpx/lib64/cmake/HPX
cmake --build build -j 8
```

(`HPX_DIR` ends in `lib/cmake/HPX` instead of `lib64/cmake/HPX` on some systems; the installer prints the right one. If CMake picks up a different MPI, add `-DMPI_CXX_COMPILER=$HOME/eduhpx_mpi/bin/mpicxx`.)

For your own program, the `CMakeLists.txt` is the usual one of an HPX program:

```cmake
cmake_minimum_required(VERSION 3.18)
project(my_app CXX)
find_package(HPX REQUIRED)
add_executable(my_app main.cpp)
target_link_libraries(my_app PRIVATE HPX::hpx HPX::iostreams_component)
```

Two things in how HPX is started matter for what you will see:

* **Parcels must go over MPI.** EduHPX shows the MPI messages below the parcels, so start with `--hpx:ini=hpx.parcel.mpi.enable=1` (and `--hpx:ini=hpx.parcel.tcp.enable=0`, so that nothing takes the TCP parcelport instead). Parcels that travel over TCP or LCI have no MPI message below them.
* With `hpx::init`, your `hpx_main` runs on locality 0 only. If every locality should run it (as in the sample), add `--hpx:run-hpx-main`.

## 4. Run it: one command

`eduhpx-run` sets up the environment, starts your launcher command, and when the program is done it merges all logs into one file, `run.csv`.

```
$EDUHPX/scripts/eduhpx-run --mpi $HOME/eduhpx_mpi --hpx $HOME/eduhpx_hpx --out $HOME/runs/my_run -- \
    mpirun --map-by ppr:4:node -n 16 ./my_app --hpx:threads=4 --hpx:run-hpx-main \
    --hpx:ini=hpx.parcel.tcp.enable=0 --hpx:ini=hpx.parcel.mpi.enable=1
```

The part after `--` is **your normal command**; `eduhpx-run` only adds, after `mpirun`, the `-x` options that carry its environment to the other nodes. `--out` and the program must be on a file system that **all nodes see**.

| option | meaning |
|---|---|
| `--mpi PREFIX`, `--hpx PREFIX` | the two installs (or set `EDUHPX_MPI_PREFIX` / `EDUHPX_HPX_PREFIX`) |
| `--out DIR` | where the logs and `run.csv` go (default: `eduhpx_run_<date>`) |
| `--name NAME` | the name shown in the viewer (default: the name of `DIR`) |
| `--no-clock`, `--clock-file F` | skip the measurement of the clock differences between nodes, or reuse an earlier one of the same job |
| `--only-collectives` | leave start-up and shutdown traffic out of `run.csv` (small files for examples) |

### In a Slurm job

```bash
#!/bin/bash
#SBATCH -N 4
#SBATCH --ntasks-per-node=4
#SBATCH --exclusive
#SBATCH -t 00:20:00

export COLL=bcast COLL_KIND=hier COLL_ITER=5 COLL_INTS=16384       # the settings of the sample program
$EDUHPX/scripts/eduhpx-run --mpi $HOME/eduhpx_mpi --hpx $HOME/eduhpx_hpx --out $HOME/runs/bcast_hier -- \
    mpirun --map-by ppr:4:node -n 16 -x COLL -x COLL_KIND -x COLL_ITER -x COLL_INTS \
    $EDUHPX/sample-app/build/hpx_collectives --hpx:threads=4 --hpx:run-hpx-main \
    --hpx:ini=hpx.parcel.tcp.enable=0 --hpx:ini=hpx.parcel.mpi.enable=1
```

* In a job with several nodes, `eduhpx-run` first measures the clock differences between the nodes (a ping-pong, as NTP does), and the merge corrects the times with them (and refines them with the fastest messages of each pair of nodes). Without that, times of different nodes cannot be compared.
* One HPX locality per MPI rank, one rank per `mpirun` process. Give HPX the cores you want with `--hpx:threads=N` (and bind with `--map-by ... PE=N` as usual).
* The sample program takes its settings from environment variables, which `mpirun` has to forward with `-x`: `COLL` = `bcast | reduce | allreduce | gather | allgather | scatter | alltoall | alltoall_large | alltoall_pairwise | scan_ex | scan_in | barrier`, `COLL_KIND` = `flat | hier`, `COLL_ARITY` (default 2), `COLL_ITER` (default 10), `COLL_INTS` (default 1024).

### What you should see

At the end of the run `eduhpx-merge` reports how well the parcels were matched to MPI messages. For the sample (a hierarchical broadcast, 8 localities on 2 nodes, 5 repetitions):

```
 clock offsets refined with the MPI messages (us, per node): compute-01 +0, compute-02 +2
eduhpx-merge: 8 MPI logs from 2 node(s), 1275 completed receives
groups: barrier x4, broadcast x5, burst x16;  1220 parcels in the window; matched to an EduMPI send: 1220 (of them 35 as zero-copy chunks); to send+recv: 1220; with an HPX recv: 1220
  HPX parcel created -> MPI send end         median       31 us  p90       91  ...
  MPI send end -> MPI recv end               median        5 us  p90       30  ...
eduhpx-merge: .../run.csv: 1220 messages
eduhpx-run: done. Open .../run.csv with EduHPX.
```

*matched to an EduMPI send* should be (nearly) all parcels. Two harmless messages may appear before the output of your program: Open MPI's *PMIx was unable to find a usable compression library* (silence it with `export PMIX_MCA_pcompress_base_silence_warning=1`), and, in a Slurm job, HPX's *--hpx:localities used when running with SLURM ... requesting a different number of localities than have been assigned by SLURM* (the program ran correctly in the tested setup).

### What is written

In `--out`:

| file | what |
|---|---|
| `parcels.loc<N>.csv` | the parcel log of locality N (HPX) |
| `eduhpx.mpi.<N>.bin` | the MPI log of rank N (measuring MPI), format in [mpi_log_format.md](mpi_log_format.md) |
| `clock_offsets.csv` | the clock differences between the nodes (several nodes only) |
| `run.csv` | the merged result: **this is the file you open** ([format](run_file_format.md)) |

It also holds the intermediate files of the merge. The logs are small, about 1 MB per rank and second of traffic. `HPX_PARCEL_LOG_MAX_MB` (default 2048) caps the log of one process.

### Without eduhpx-run

If you start your program some other way, set what `eduhpx-run` sets and merge by hand:

```
export PATH=$HOME/eduhpx_mpi/bin:$PATH
export LD_LIBRARY_PATH=$HOME/eduhpx_mpi/lib:$HOME/eduhpx_hpx/lib64:$LD_LIBRARY_PATH
export HPX_PARCEL_LOG=$OUT/parcels          # process N writes $OUT/parcels.loc<N>.csv
export EDUHPX_MPI_LOG_DIR=$OUT              # rank N writes $OUT/eduhpx.mpi.<N>.bin
# ... start your program, with the variables forwarded to all nodes ...
python3 $EDUHPX/scripts/eduhpx-merge $OUT -o $OUT/run.csv --run my_run
```

## 5. Look at it

Copy `run.csv` to your laptop and open it with the EduHPX viewer ([download](../README.md#download), or build it from `gui/`): *Open run...*, or drag the file onto the window.

* Collectives (a broadcast, a reduce, ...) are **one group each**, everything else is cut into bursts by pauses. `<` and `>` step through the groups; the strip shows all of them.
* *By locality* shows one lane per locality in time, with the MPI send and receive of every parcel and what HPX did before and after (prepare, pick up, run the action). *By message* shows the life of every message below each other.
* For a collective: *Tree* and *3D tree*, and the *Critical path* button. The **3D tree** uses the node of every locality, which `eduhpx-merge` writes into `run.csv` from the MPI logs (for older run files the localities are assumed to be spread evenly over the nodes); it shows your cluster as glass cubes (one per node) with the localities inside, green lines for sends and red lines for receives, and colours for the send/receive ratio, the largest sender or receiver, or the arrival of the data. Click a cube to look at it. See [the viewer](../gui/README.md).

The result of the sample, hierarchical broadcast of 16 localities on 4 nodes, is one of the built-in examples (*File > Examples*).

## Cost of the measurement

Measuring is not free: the measuring MPI and the parcel log slow the program down a little, so use it to *understand* a run, not to time it. The numbers, measured with a communication-only benchmark (a worst case), are in the [README](../README.md#overhead). Do not attach the Tracy profiler on top: a connected Tracy capture slows HPX down by a factor of 10 to 25.

## If something does not work

| what you see | what to check |
|---|---|
| `eduhpx-merge`: *no eduhpx.mpi.\<rank\>.bin files* | The program did not run with the measuring MPI. `ldd ./my_app \| grep libmpi` must point into `$HOME/eduhpx_mpi/lib`; rebuild the program against this HPX, and check that `LD_LIBRARY_PATH` reaches all nodes (`eduhpx-run` forwards it with `-x`). |
| No `parcels.loc<N>.csv` | The program does not use the patched HPX (rebuilt against `--prefix` of `install-hpx.sh`?), or `HPX_PARCEL_LOG` did not reach the processes. |
| Many parcels *without MPI message* (dashed in the trees) | A few are normal (the viewer counts the parcels it could not match). Many mean the parcels did not go over MPI: check `--hpx:ini=hpx.parcel.mpi.enable=1` and `hpx.parcel.tcp.enable=0`. |
| `mpirun: command not found` in `eduhpx-run` | Give `--mpi PREFIX` (the measuring MPI) or load your MPI first. |
| The times of different nodes do not fit | Run inside one Slurm job with several nodes so that the clock measurement runs, or give `--clock-file`. On one node no measurement is needed. |
| The build is very slow | Use `--build-dir /tmp/...` (a local disk), not the home directory. |
| `install-mpi.sh`: *checksum ... expected ...* | The file is damaged or not the pinned tarball. Download again; for another tarball give its checksum with `--sha256`. |
| The *3D tree* button shows a note instead of a view | The viewer was built without Qt Quick 3D or runs without a graphics driver for it. All other views work. |

If a run is very large, use `--only-collectives`, fewer iterations, or fewer localities for the trace.
