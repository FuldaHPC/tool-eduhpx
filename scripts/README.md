# Scripts (work in progress)

What exists and what does not yet, as of 2026-11-05.

| Script | State |
|---|---|
| `install-hpx.sh` | Done and tested on a Linux cluster: downloads HPX at the pinned commit, applies `../patches/hpx-e65a7a3c.patch` (parcel log), builds and installs it against a given MPI. See [../docs/install.md](../docs/install.md). Not tested on macOS. |
| `install-mpi.sh` | Not written yet. The measuring MPI is the branch `eduhpx_mpi_data` of the EduMPI repository (database-free, writes `eduhpx.mpi.<rank>.bin`, format in [../docs/mpi_log_format.md](../docs/mpi_log_format.md)). |
| `eduhpx-run` | Not written yet: sets the environment, measures the clock offsets between nodes, starts the program, calls the merge. |
| `eduhpx-merge` | Not written yet: raw logs of HPX and MPI to the run file ([../docs/run_file_format.md](../docs/run_file_format.md)). |

Known cost of the measurement (one old cluster, flat broadcast of 64 KiB on one node): the patched HPX with the log
on is about 20 % slower than pure HPX on the same MPI; the measuring MPI adds about 14 % to pure HPX. Details and
caveats are in the EduHPX project notes.
