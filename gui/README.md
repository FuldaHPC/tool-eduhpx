# EduHPX viewer

Qt 6 Quick app that opens an EduHPX run file (CSV, see [../docs/run_file_format.md](../docs/run_file_format.md)).
No database, no 3D view, no network.

## Build (Qt 6.5 or newer, CMake 3.19 or newer)

    cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/Qt/6.x/<platform>
    cmake --build build

## Start

    build/eduhpx.app/Contents/MacOS/eduhpx run.csv     # macOS
    build/eduhpx run.csv                               # Linux, Windows

or start it without an argument and use *Open run...*, *File > Open*, drag a file onto the window, or start with one of the built-in examples (the start screen lists them, *File > Examples...* too).

## A tour of the window

**Top:** the run, and the group you look at. Collectives (a broadcast) are one group each; everything else is cut into
bursts by pauses. `<` and `>` step through the groups. The strip under the summary shows all groups: blue-grey are
collectives, grey bursts, the white one is the group you look at.

**Summary:** number of messages and data volume of the group, and where the time went. The big bar has two modes:

- *Default: the time of all messages added up* (MPI, HPX, waiting). The messages run in parallel, so this is more than
  wall-clock time; it is not CPU time either, because it contains waiting (open sends, requests waiting at their
  parent). Below it: MPI and HPX time per message, with the pure transfer time of MPI in brackets.
- *With the Critical path button on:* the chain of messages that decided when the broadcast finished, in **wall-clock
  time** ("2.70 ms of 4.87 ms"), split into *HPX prepares*, *MPI* (with the number of hops), *HPX picks up*, *request
  waits at parent* and *action*. The added-up time moves into a small second line.

**Views**

| Button | What you see |
|---|---|
| *By locality* | One lane per locality, in time. Arrows connect a send to its receive. The first lane (the root of a broadcast) is drawn in several rows, one per message. |
| *By message* | One row per message (`L4 > L0 246 B get`): the whole life of every message below each other. |
| *Tree* | The broadcast as a tree of localities (with many localities the tree shrinks and shows the times of an edge when you hover it): white arrows carry the data from the parent, orange arrows are the requests to the parent, the numbers are the time of each hop. |
| *Critical path* | Switches the summary to the critical path and marks it in gold in the views (on/off). |
| *Arrows* | All, only *Data* (the large messages) or only *Requests*. |
| *Reset zoom* | Mouse wheel zooms, dragging moves; this resets. |

Hover a piece of work or an arrow for its numbers (size, time in MPI, what HPX did).

### Colours

| | |
|---|---|
| grey | waits for data (the parent has not set it yet) |
| orange | HPX prepares the parcel |
| green | MPI send call |
| green striped | the send request is still open: MPI is still working on the message |
| red | MPI receive |
| blue frame | time inside MPI |
| light orange | HPX picks up the received message |
| yellow | the action runs |
| brown | a request waits at its parent until the reply is created |
| white tick | HPX notices that the message was sent |

Green and red are the same colours as in the EduMPI 3D view.

### By message

<img src="../screenshots/flat_broadcast_by_message.png" width="900">

### Hierarchical broadcast

<img src="../screenshots/hierarchical_broadcast_by_locality.png" width="900">

## Headless preview (for tests)

    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software eduhpx ../examples/bcast_flat_16loc_4nodes.csv \
        --render out/ broadcast:3:locality broadcast:3:tree

writes `out/broadcast3_locality.png` and `out/broadcast3_tree.png` (`kind:number:view`, view = locality | message | tree).
