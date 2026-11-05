<p align="center"><img src="assets/logo.png" alt="EduHPX" width="260"></p>

# EduHPX

Viewer for HPX runs: HPX parcels and the MPI messages below them on one timeline (by locality, by message, tree of a
broadcast, critical path, summary). It reads a run file (CSV, see `docs/run_file_format.md`). No database, no 3D view.

## Build (Qt 6.5 or newer, CMake)

    cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/Qt/6.x/<platform>
    cmake --build build

## Run

    build/eduhpx.app/Contents/MacOS/eduhpx run.csv     # macOS;  build/eduhpx run.csv  on Linux
    # or File > Open, drag a file onto the window, File > Examples

## Headless preview (test)

    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software eduhpx examples/flat_broadcast_16loc_4nodes.csv \
        broadcast:3:locality broadcast:3:tree --render out/

writes `out/broadcast3_locality.png`, `out/broadcast3_tree.png` (`kind:number:view`, view = locality | message | tree).

## Examples

`examples/*.csv` were made from merged runs of the old tool with `tools/json_to_csv.py`.

BSD-3-Clause, see LICENSE and THIRD_PARTY_NOTICES.md.
