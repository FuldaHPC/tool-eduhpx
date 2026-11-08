# Scripts (work in progress)

What exists and what does not yet (2026-11-05). Everything was tested on one Linux cluster (Open MPI, UCX, Slurm), not on macOS.

| Script | State |
|---|---|
| `install-hpx.sh` | Done and tested on a Linux cluster: downloads HPX at the pinned commit, applies `../patches/hpx-ec3b59b1.patch` (parcel log), builds and installs it against a given MPI. See [../docs/install.md](../docs/install.md). Not tested on macOS. |
| `install-mpi.sh` | Checks the checksum of the measuring MPI tarball, builds it from the unpacked archive, installs it and runs a small test (4 ranks, files read back). The measuring MPI is the branch `eduhpx_mpi_data` of the EduMPI repository (database-free, writes `eduhpx.mpi.<rank>.bin`, format in [../docs/mpi_log_format.md](../docs/mpi_log_format.md)). The tarball is **not published as a download yet**: until then give the file with `--tarball FILE`. See [../docs/mpi_tarball.md](../docs/mpi_tarball.md). Linux only, not tested on macOS. |
| `eduhpx-run` | Done, tested on 4 nodes (Slurm): sets the environment, measures the clock offsets between nodes, starts the program, makes `run.csv`. One command, see below. |
| `eduhpx-merge` | Done (called by `eduhpx-run`, can be used alone): raw logs of HPX and MPI to the run file ([../docs/run_file_format.md](../docs/run_file_format.md)). Python, standard library only. |

## One command

    eduhpx-run --mpi $HOME/eduhpx_mpi --hpx $HOME/eduhpx_hpx --out my_run -- \
        mpirun -np 16 ./my_hpx_app --hpx:ini=hpx.parcel.mpi.enable=1

The program runs with the measuring MPI and the patched HPX, and `my_run/run.csv` comes out; open it with EduHPX.
`--out` must be on a file system that all nodes see. In a Slurm job with several nodes the clock offsets are measured
automatically (outside Slurm, or with `--no-clock`, no offsets are measured, which is fine on one node). Tested: a flat and a hierarchical broadcast of 20 repetitions, 16 localities on 4 nodes, about 20 seconds;
99.6 % and 99.8 % of the parcels were matched to MPI messages, and the viewer opens the result.

Known cost of the measurement (one old cluster, flat broadcast of 64 KiB on one node): the patched HPX with the log
on is about 13 % slower than pure HPX on the same MPI (about 6 % with the log off); the measuring MPI adds about 14 % to pure HPX. Details and
caveats are in the EduHPX project notes.
