#!/usr/bin/env bash
# EduHPX: build and install HPX with the EduHPX parcel log.
#
# Downloads HPX at one pinned commit (a tarball from GitHub, checksum checked), applies
# patches/hpx-<commit>.patch (the parcel log, see docs/install.md), configures HPX with the MPI parcel port
# of the measuring MPI (eduhpx_mpi_data) and installs it. HPX itself is not part of this repository.
#
#   scripts/install-hpx.sh --mpi-prefix ~/eduhpx_mpi --prefix ~/eduhpx_hpx [--jobs 16]
#
# Needs: cmake >= 3.18, a C++17 compiler (the one the MPI wrappers use), make or ninja, curl or wget, tar, patch or git,
# internet access (HPX downloads Boost, asio and Tracy sources while it configures).
set -euo pipefail

HPX_COMMIT=ec3b59b1fa0b1b5decf21141983c1b725d9323cf
HPX_TARBALL_SHA256=3f2fb2158d00e25c79a3d9f58451afe1f46b797c667d2202776842fee932c865
HPX_URL=https://github.com/TheHPXProject/hpx/archive/${HPX_COMMIT}.tar.gz
BOOST_VERSION=1.86.0

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
patch_file=$here/../patches/hpx-${HPX_COMMIT:0:8}.patch

usage() {
    cat <<USAGE
usage: install-hpx.sh [options]
  --mpi-prefix DIR    measuring MPI (eduhpx_mpi_data); default \$EDUHPX_MPI_PREFIX, else ~/eduhpx_mpi if it exists
  --prefix DIR        install directory of HPX              (default ~/eduhpx_hpx)
  --jobs N            parallel build jobs                   (default: number of cores)
  --build-dir DIR     build directory                       (default: a new directory in \${TMPDIR:-/tmp}; use a local disk,
                      not a network file system, the build is much faster there)
  --download-dir DIR  where the HPX tarball is kept         (default ~/.cache/eduhpx)
  --source-dir DIR    use this unpacked HPX source at the pinned commit instead of downloading it (it is copied, not changed)
  --hwloc-root DIR    hwloc to use                          (default: the MPI prefix if it contains one, else the system's)
  --keep-build        do not delete the build directory afterwards
  -h, --help
Pinned HPX commit: ${HPX_COMMIT}
USAGE
}

die() { echo "install-hpx: $*" >&2; exit 1; }
info() { echo "install-hpx: $*"; }

mpi_prefix=${EDUHPX_MPI_PREFIX:-}
prefix=$HOME/eduhpx_hpx
jobs=
build_dir=
download_dir=$HOME/.cache/eduhpx
source_dir=
hwloc_root=
keep_build=0

while [ $# -gt 0 ]; do
    case $1 in
        --mpi-prefix) mpi_prefix=${2:?}; shift 2 ;;
        --prefix) prefix=${2:?}; shift 2 ;;
        --jobs|-j) jobs=${2:?}; shift 2 ;;
        --build-dir) build_dir=${2:?}; shift 2 ;;
        --download-dir) download_dir=${2:?}; shift 2 ;;
        --source-dir) source_dir=${2:?}; shift 2 ;;
        --hwloc-root) hwloc_root=${2:?}; shift 2 ;;
        --keep-build) keep_build=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option $1" ;;
    esac
done

# ---------------------------------------------------------------- checks
if [ -z "$mpi_prefix" ] && [ -x "$HOME/eduhpx_mpi/bin/mpicxx" ]; then
    mpi_prefix=$HOME/eduhpx_mpi
fi
[ -n "$mpi_prefix" ] || die "no MPI: give --mpi-prefix DIR (the install directory of the measuring MPI, eduhpx_mpi_data) or set EDUHPX_MPI_PREFIX"
for w in mpicc mpicxx; do
    [ -x "$mpi_prefix/bin/$w" ] || die "$mpi_prefix/bin/$w not found: $mpi_prefix is not an MPI installation (see docs/install.md to install the measuring MPI)"
done
[ -f "$patch_file" ] || die "patch $patch_file is missing (incomplete checkout of EduHPX?)"

command -v cmake >/dev/null 2>&1 || die "cmake not found (version 3.18 or newer is needed)"
cmake_version=$(cmake --version | head -1 | sed -E 's/[^0-9]*([0-9]+\.[0-9]+).*/\1/')
case $cmake_version in
    [4-9].*|3.1[8-9]|3.[2-9][0-9]) ;;
    *) die "cmake $cmake_version is too old (3.18 or newer is needed)" ;;
esac

# compiler: the one behind the MPI wrappers, so that HPX and MPI agree
cxx=$("$mpi_prefix/bin/mpicxx" --showme:command 2>/dev/null | head -1 || true)
cc=$("$mpi_prefix/bin/mpicc" --showme:command 2>/dev/null | head -1 || true)
[ -n "$cxx" ] || cxx=${CXX:-c++}
[ -n "$cc" ] || cc=${CC:-cc}
command -v "$cxx" >/dev/null 2>&1 || die "C++ compiler '$cxx' not found"
command -v "$cc" >/dev/null 2>&1 || die "C compiler '$cc' not found"

if command -v ninja >/dev/null 2>&1; then
    generator=Ninja
elif command -v make >/dev/null 2>&1; then
    generator="Unix Makefiles"
else
    die "neither ninja nor make found"
fi

for t in tar; do command -v $t >/dev/null 2>&1 || die "$t not found"; done
if command -v patch >/dev/null 2>&1; then
    apply_patch() { patch -p1 -s -d "$1" < "$patch_file"; }
elif command -v git >/dev/null 2>&1; then
    apply_patch() { git -C "$1" apply -p1 "$patch_file"; }
else
    die "neither patch nor git found (needed to apply the HPX patch)"
fi
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

if [ -z "$hwloc_root" ]; then
    for d in "$mpi_prefix"; do
        if ls "$d"/lib/libhwloc.* >/dev/null 2>&1 && [ -f "$d/include/hwloc.h" ]; then hwloc_root=$d; fi
    done
fi

own_build_dir=0
if [ -z "$build_dir" ]; then
    build_dir=$(mktemp -d "${TMPDIR:-/tmp}/eduhpx-hpx-build.XXXXXX")
    own_build_dir=1
else
    mkdir -p "$build_dir"
fi
build_dir=$(cd "$build_dir" && pwd)
case $build_dir in
    /home/*|/Users/*) info "note: build directory $build_dir is in a home directory; on a cluster this is often a slow network file system (use --build-dir /tmp/...)" ;;
esac

# ---------------------------------------------------------------- source
src=$build_dir/hpx-src
if [ -n "$source_dir" ]; then
    [ -f "$source_dir/CMakeLists.txt" ] || die "$source_dir is not an HPX source directory"
    info "copying HPX source from $source_dir"
    rm -rf "$src"; mkdir -p "$src"
    (cd "$source_dir" && tar cf - --exclude=.git .) | (cd "$src" && tar xf -)
else
    mkdir -p "$download_dir"
    tarball=$download_dir/hpx-${HPX_COMMIT:0:8}.tar.gz
    if [ ! -f "$tarball" ] || [ "$(sha256 "$tarball")" != "$HPX_TARBALL_SHA256" ]; then
        info "downloading $HPX_URL"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$tarball.part" "$HPX_URL" || die "download failed (internet access needed)"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$tarball.part" "$HPX_URL" || die "download failed (internet access needed)"
        else
            die "neither curl nor wget found"
        fi
        mv "$tarball.part" "$tarball"
    fi
    got=$(sha256 "$tarball")
    [ "$got" = "$HPX_TARBALL_SHA256" ] || die "checksum of $tarball is $got, expected $HPX_TARBALL_SHA256 (delete the file and retry; if it happens again GitHub changed the archive, use --source-dir with a git checkout of $HPX_COMMIT)"
    info "checksum ok"
    rm -rf "$src"; mkdir -p "$src"
    tar xzf "$tarball" -C "$src" --strip-components=1
fi
info "applying $(basename "$patch_file")"
apply_patch "$src" || die "the patch does not apply: the source is not the pinned commit $HPX_COMMIT"

# ---------------------------------------------------------------- configure, build, install
info "MPI: $mpi_prefix   compiler: $(command -v "$cxx")   generator: $generator   jobs: $jobs"
[ -n "$hwloc_root" ] && info "hwloc: $hwloc_root"
cmake_args=(
    -S "$src" -B "$build_dir/build" -G "$generator"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="$prefix"
    -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx"
    -DMPI_C_COMPILER="$mpi_prefix/bin/mpicc" -DMPI_CXX_COMPILER="$mpi_prefix/bin/mpicxx"
    -DHPX_WITH_NETWORKING=ON -DHPX_WITH_PARCELPORT_MPI=ON
    -DHPX_WITH_FETCH_BOOST=ON -DHPX_WITH_BOOST_VERSION=$BOOST_VERSION -DHPX_WITH_FETCH_ASIO=ON
    -DHPX_WITH_MALLOC=system -DHPX_WITH_MAX_CPU_COUNT=64
    # Tracy is only the compile gate of the parcel hooks; it is never connected at run time
    -DHPX_WITH_TRACY=ON -DHPX_WITH_PARCEL_PROFILING=ON
    -DHPX_WITH_TRACING_LIFECYCLE_EVENTS=OFF -DHPX_WITH_TRACING_WORK_STEALING_EVENTS=OFF -DHPX_WITH_TRACING_CAUSAL_EVENTS=OFF
    # lock events (HPX PR 8001, off by default since ec3b59b) cost about 10 % with Tracy compiled in, even without a profiler
    -DHPX_WITH_TRACING_LOCK_EVENTS=OFF
    -DHPX_WITH_EXAMPLES=OFF -DHPX_WITH_TESTS=OFF -DHPX_WITH_DOCUMENTATION=OFF
)
[ -n "$hwloc_root" ] && cmake_args+=(-DHWLOC_ROOT="$hwloc_root")
# the MPI of the measuring branch sits in a private prefix: find it before any system MPI
cmake_args+=(-DCMAKE_PREFIX_PATH="$mpi_prefix")

export PATH="$mpi_prefix/bin:$PATH"
if [ -d "$mpi_prefix/lib" ]; then
    export LD_LIBRARY_PATH="$mpi_prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export DYLD_LIBRARY_PATH="$mpi_prefix/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
fi

cmake "${cmake_args[@]}" > "$build_dir/configure.log" 2>&1 || { tail -30 "$build_dir/configure.log" >&2; die "configure failed, full log: $build_dir/configure.log"; }
info "configured, building (this takes a while)"
cmake --build "$build_dir/build" -j "$jobs" > "$build_dir/build.log" 2>&1 || { tail -30 "$build_dir/build.log" >&2; die "build failed, full log: $build_dir/build.log"; }
info "installing to $prefix"
cmake --install "$build_dir/build" > "$build_dir/install.log" 2>&1 || { tail -30 "$build_dir/install.log" >&2; die "install failed, full log: $build_dir/install.log"; }

# ---------------------------------------------------------------- check and summary
libdir=$prefix/lib64; [ -d "$libdir" ] || libdir=$prefix/lib
hpx_dir=$libdir/cmake/HPX
core=$(ls "$libdir"/libhpx_core.* 2>/dev/null | head -1 || true)
if [ -n "$core" ] && command -v nm >/dev/null 2>&1; then
    # (not "nm | grep -q": with pipefail the early exit of grep makes the pipeline fail)
    symbols=$(nm -D "$core" 2>/dev/null || nm -gU "$core" 2>/dev/null || true)
    if [[ $symbols == *parcel_created_impl* ]]; then
        info "check: the parcel log is in the installed HPX"
    else
        die "the installed HPX has no parcel log (symbol parcel_created_impl missing in $core)"
    fi
fi

mkdir -p "$prefix/share/eduhpx"
{
    echo "hpx_commit=$HPX_COMMIT"
    echo "patch=$(basename "$patch_file") sha256=$(sha256 "$patch_file")"
    echo "mpi_prefix=$mpi_prefix"
    echo "compiler=$(command -v "$cxx")"
    echo "boost=$BOOST_VERSION"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$prefix/share/eduhpx/hpx-build-info.txt"

if [ "$keep_build" = 0 ] && [ "$own_build_dir" = 1 ]; then rm -rf "$build_dir"; else info "build directory kept: $build_dir"; fi

cat <<DONE

HPX is installed in $prefix  (commit ${HPX_COMMIT:0:8} with the EduHPX parcel log).
To build your program against it:
    cmake ... -DHPX_DIR=$hpx_dir -DMPI_CXX_COMPILER=$mpi_prefix/bin/mpicxx
To run it (eduhpx-run sets this for you):
    export LD_LIBRARY_PATH=$libdir:$mpi_prefix/lib:\$LD_LIBRARY_PATH
    export HPX_PARCEL_LOG=<dir>/parcels     # writes <dir>/parcels.loc<rank>.csv per process
    export HPX_PARCEL_LOG_MAX_MB=2048       # size cap per process (optional)
DONE
