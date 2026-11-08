#!/usr/bin/env bash
# EduHPX: build and install the measuring MPI.
#
# The measuring MPI is Open MPI with the EduMPI instrumentation (branch eduhpx_mpi_data of the EduMPI repository). It writes
# one binary file per rank (eduhpx.mpi.<rank>.bin) into $EDUHPX_MPI_LOG_DIR. It comes as a source tarball; this script
# checks the checksum, builds it from the unpacked archive, installs it and runs a small test.
#
#   scripts/install-mpi.sh --prefix ~/eduhpx_mpi [--tarball FILE|URL] [--jobs 16]
#
# Needs: a C compiler, make, tar, curl or wget (only to download the tarball). UCX development files only if you want the
# UCX transport. Linux; the build takes about 35 minutes with 16 cores. Not tested on macOS.
set -euo pipefail

MPI_NAME=eduhpx_mpi_data-5.0.11rc1-eduhpx1
MPI_TARBALL_SHA256=64e1324acf5888861e042e5ad05afc351cf6ed2d5a75d667cf0322d01d5fa1d3
# The tarball is not published as a download yet: until it is, give it with --tarball FILE. This is where it will be.
MPI_URL=https://github.com/AnnaLena77/EduMPI/releases/download/eduhpx-mpi-5.0.11rc1-eduhpx1/${MPI_NAME}.tar.gz

usage() {
    cat <<USAGE
usage: install-mpi.sh [options]
  --prefix DIR        install directory of the measuring MPI  (default ~/eduhpx_mpi)
  --tarball FILE|URL  the tarball ${MPI_NAME}.tar.gz, a file or a URL (default: the release URL)
  --sha256 HEX        expected checksum of the tarball        (default: the one pinned in this script)
  --jobs N            parallel build jobs                     (default: number of cores)
  --build-dir DIR     build directory                         (default: a new directory in \${TMPDIR:-/tmp}; use a local disk,
                      not a network file system, configure and make are much slower there)
  --download-dir DIR  where a downloaded tarball is kept      (default ~/.cache/eduhpx)
  --no-test           do not run the test after the install
  --keep-build        do not delete the build directory afterwards
  -h, --help
Pinned tarball: ${MPI_NAME}.tar.gz  sha256 ${MPI_TARBALL_SHA256}
USAGE
}

die() { echo "install-mpi: $*" >&2; exit 1; }
info() { echo "install-mpi: $*"; }

prefix=$HOME/eduhpx_mpi
tarball=$MPI_URL
sha_expected=$MPI_TARBALL_SHA256
jobs=
build_dir=
download_dir=$HOME/.cache/eduhpx
run_test=1
keep_build=0

while [ $# -gt 0 ]; do
    case $1 in
        --prefix) prefix=${2:?}; shift 2 ;;
        --tarball) tarball=${2:?}; shift 2 ;;
        --sha256) sha_expected=${2:?}; shift 2 ;;
        --jobs|-j) jobs=${2:?}; shift 2 ;;
        --build-dir) build_dir=${2:?}; shift 2 ;;
        --download-dir) download_dir=${2:?}; shift 2 ;;
        --no-test) run_test=0; shift ;;
        --keep-build) keep_build=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option $1" ;;
    esac
done

# ---------------------------------------------------------------- checks
command -v tar >/dev/null 2>&1 || die "tar not found"
command -v make >/dev/null 2>&1 || die "make not found"
command -v "${CC:-cc}" >/dev/null 2>&1 || die "no C compiler found (cc, or set CC)"
if command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
    sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    die "neither sha256sum nor shasum found"
fi

if [ -z "$jobs" ]; then
    jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
fi

if [ -e "$prefix/bin/mpicc" ]; then
    info "note: $prefix already contains an MPI; it is overwritten (give another --prefix to keep it)"
fi
mkdir -p "$prefix" || die "cannot create $prefix"
prefix=$(cd "$prefix" && pwd)

own_build_dir=0
if [ -z "$build_dir" ]; then
    build_dir=$(mktemp -d "${TMPDIR:-/tmp}/eduhpx-mpi-build.XXXXXX")
    own_build_dir=1
else
    mkdir -p "$build_dir"
fi
build_dir=$(cd "$build_dir" && pwd)
case $build_dir in
    /home/*|/Users/*) info "note: build directory $build_dir is in a home directory; on a cluster this is often a slow network file system (use --build-dir /tmp/...)" ;;
esac

# ---------------------------------------------------------------- tarball
case $tarball in
    http://*|https://*)
        mkdir -p "$download_dir"
        file=$download_dir/${MPI_NAME}.tar.gz
        if [ ! -f "$file" ] || [ "$(sha256 "$file")" != "$sha_expected" ]; then
            info "downloading $tarball"
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL -o "$file.part" "$tarball" || { rm -f "$file.part"; die "download failed. The tarball may not be published yet: if you have the file, use --tarball FILE"; }
            elif command -v wget >/dev/null 2>&1; then
                wget -q -O "$file.part" "$tarball" || { rm -f "$file.part"; die "download failed. The tarball may not be published yet: if you have the file, use --tarball FILE"; }
            else
                die "neither curl nor wget found (or give the tarball as a file with --tarball FILE)"
            fi
            mv "$file.part" "$file"
        fi
        ;;
    *)
        [ -f "$tarball" ] || die "$tarball not found"
        file=$tarball
        ;;
esac
got=$(sha256 "$file")
[ "$got" = "$sha_expected" ] || die "checksum of $file is $got, expected $sha_expected (a wrong or damaged file; for another version of the tarball give its checksum with --sha256)"
info "checksum ok"

src=$build_dir/src
rm -rf "$src"; mkdir -p "$src"
tar xzf "$file" -C "$src" --strip-components=1
[ -x "$src/configure" ] || die "$file does not contain a configure script: it is not the EduHPX measuring MPI tarball"
[ -f "$src/ompi/mpi/c/edumpi_req_ext.h" ] || die "$file is Open MPI, but without the EduHPX instrumentation"

# ---------------------------------------------------------------- configure, build, install
info "prefix: $prefix   jobs: $jobs   build directory: $build_dir"
info "configure (about 15 minutes)"
(cd "$src" && ./configure --prefix="$prefix" --with-pmix=internal --with-hwloc=internal --with-prrte=internal) \
    > "$build_dir/configure.log" 2>&1 || { tail -30 "$build_dir/configure.log" >&2; die "configure failed, full log: $build_dir/configure.log"; }
info "make (about 20 minutes with 16 cores)"
make -C "$src" -j "$jobs" > "$build_dir/make.log" 2>&1 || { tail -30 "$build_dir/make.log" >&2; die "make failed, full log: $build_dir/make.log"; }
info "installing to $prefix"
make -C "$src" install > "$build_dir/install.log" 2>&1 || { tail -30 "$build_dir/install.log" >&2; die "install failed, full log: $build_dir/install.log"; }

[ -x "$prefix/bin/mpicc" ] && [ -x "$prefix/bin/mpirun" ] || die "the install is incomplete: $prefix/bin/mpicc or mpirun is missing"
transports=$("$prefix/bin/ompi_info" --parsable 2>/dev/null | sed -n 's/^mca:pml:\([a-z0-9]*\):version.*/\1/p' | sort -u | tr '\n' ' ' || true)
info "installed: transports (pml) $transports"

# ---------------------------------------------------------------- test
# 4 ranks send and receive, then the files of rank 0 are read back
if [ "$run_test" = 1 ]; then
    test_src=$src/tools/eduhpx_mpi_test.c
    dump=$src/tools/eduhpx_dump.py
    if [ -f "$test_src" ] && command -v python3 >/dev/null 2>&1; then
        mkdir -p "$build_dir/test"
        "$prefix/bin/mpicc" "$test_src" -o "$build_dir/test/eduhpx_mpi_test" > "$build_dir/test/compile.log" 2>&1 \
            || { tail -20 "$build_dir/test/compile.log" >&2; die "the test program does not compile, log: $build_dir/test/compile.log"; }
        rm -f "$build_dir"/test/eduhpx.mpi.*.bin
        # a login node may have fewer cores than ranks; stay on the shared-memory transport so that no network is needed
        (cd "$build_dir/test" && EDUHPX_MPI_LOG_DIR="$build_dir/test" OMPI_MCA_pml=ob1 OMPI_MCA_btl=self,vader \
            "$prefix/bin/mpirun" -np 4 --oversubscribe ./eduhpx_mpi_test 2000) > "$build_dir/test/run.log" 2>&1 \
            || { tail -20 "$build_dir/test/run.log" >&2; die "the test run failed, log: $build_dir/test/run.log (see also docs/install.md)"; }
        [ -s "$build_dir/test/eduhpx.mpi.0.bin" ] || die "the test run wrote no eduhpx.mpi.0.bin: the measuring is not active"
        summary=$(python3 -I "$dump" --summary "$build_dir/test/eduhpx.mpi.0.bin" 2>&1 | head -3 || true)
        info "check: the test run wrote its files; rank 0:"
        echo "$summary" | sed 's/^/    /'
    else
        info "no test (tools/eduhpx_mpi_test.c or python3 missing)"
    fi
fi

mkdir -p "$prefix/share/eduhpx"
{
    echo "mpi=$MPI_NAME"
    echo "tarball_sha256=$got"
    echo "transports=$transports"
    echo "compiler=$(command -v "${CC:-cc}")"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$prefix/share/eduhpx/mpi-build-info.txt"

if [ "$keep_build" = 0 ] && [ "$own_build_dir" = 1 ]; then rm -rf "$build_dir"; else info "build directory kept: $build_dir"; fi

cat <<DONE

The measuring MPI is installed in $prefix  ($MPI_NAME).
Next: install HPX with the parcel log against it:
    scripts/install-hpx.sh --mpi-prefix $prefix --prefix ~/eduhpx_hpx
To measure a program with MPI alone (no HPX):
    export PATH=$prefix/bin:\$PATH
    export EDUHPX_MPI_LOG_DIR=<dir>         # writes <dir>/eduhpx.mpi.<rank>.bin per rank
DONE
