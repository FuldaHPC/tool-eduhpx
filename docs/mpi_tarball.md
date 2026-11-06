# The measuring MPI as a tarball

The measuring MPI (Open MPI with the EduMPI instrumentation, no database) lives on the branch `eduhpx_mpi_data` of
the EduMPI repository. Users get it as a source tarball, so they need no autotools and no Sphinx.

Current file: `eduhpx_mpi_data-5.0.11rc1-eduhpx1.tar.gz` (57 MB), checked with a build from the unpacked archive and a
test run with UCX and ob1 (4 ranks, `tools/eduhpx_mpi_test.c`, files read with `tools/eduhpx_dump.py`).

## Build from the tarball (user)

    tar xzf eduhpx_mpi_data-5.0.11rc1-eduhpx1.tar.gz
    cd eduhpx_mpi_data-5.0.11rc1-eduhpx1
    ./configure --prefix=$HOME/eduhpx_mpi --with-pmix=internal --with-hwloc=internal --with-prrte=internal
    make -j 16 && make install

Needs a C compiler and make; UCX (development files) only for the UCX transport. About 20 minutes with 16 cores.
`-DENABLE_ANALYSIS=1` is set by default. Run with `EDUHPX_MPI_LOG_DIR=<dir>` to get `eduhpx.mpi.<rank>.bin`.

## Make a new tarball (maintainer), also for a new Open MPI version

1. Move the branch to the new Open MPI release: add the upstream repository as a remote, fetch the tag, rebase or merge
   `eduhpx_mpi_data` onto it. Conflicts are possible in `ompi/mpi/c/*.c` (the wrappers), `ompi/mpi/c/init.[ch]`,
   `ompi/mca/pml/ob1/*` and `ompi/mca/pml/ucx/*`; the shared hook code is in `ompi/mpi/c/edumpi_req_ext.h`.
2. `git submodule update --init --recursive` (PMIx, PRRTE, hwloc, libevent come in with the tarball).
3. Tools on the build machine: autoconf, automake, libtool, flex, perl, python3 with Sphinx and
   `docs/requirements.txt` (`make dist` builds the documentation and puts it into the archive).
4. `./autogen.pl`, then `./configure --with-pmix=internal --with-hwloc=internal --with-prrte=internal`, then
   `make dist SPHINX_OPTS="--keep-going -j auto"` (the default `-W` makes every Sphinx warning an error).
   `.mailmap` must not have a duplicate e-mail address, or `make dist` stops while it writes `AUTHORS`.
5. Rename the top directory to `eduhpx_mpi_data-<version>-eduhpx<n>`, pack it again, write the SHA-256 file.
6. Test with the archive only: unpack, `configure` (without Sphinx in the PATH), `make`, `make install`, run
   `tools/eduhpx_mpi_test.c` with `OMPI_MCA_pml=ucx` and `ob1`, read the files with `tools/eduhpx_dump.py`.
7. Upload the archive and the `.sha256` file to a release of the EduMPI repository.

Time on the cluster (16 cores, node-local disk): autogen 5 min, configure 17 min, `make dist` 9 min, build from the
archive 35 min. Never build on the shared home directory, it is too slow. The work of step 1 is the real effort.
