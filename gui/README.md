# EduHPX viewer

Qt 6 Quick app that opens an EduHPX run file (CSV, see [../docs/run_file_format.md](../docs/run_file_format.md)).
No database, no network. The tree can also be shown in 3D (needs Qt Quick 3D, see below).

## Build (Qt 6.5 or newer, CMake 3.19 or newer)

    cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/Qt/6.x/<platform>
    cmake --build build

The 3D tree needs the Qt module *Qt Quick 3D* (in the Qt installer it is one of the additional libraries; with `aqt`: `--modules qtquick3d`). Without it
the viewer builds and runs, and the *3D tree* button shows a note instead of the view.

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
| *Tree* | A collective as a tree of localities (a star if it is flat): for a broadcast or scatter the data moves down, for a reduce or gather up (with many localities the tree shrinks and shows the times of an edge when you hover it): white arrows carry the data from the parent, orange arrows are the requests to the parent, the numbers are the time of each hop. |
| *3D tree* | The tree with the nodes of the cluster, in 3D: see below. |
| *Critical path* | Switches the summary to the critical path and marks it in gold in the views (on/off). |
| *Arrows* | All, only *Data* (the large messages) or only *Requests*. |
| *Reset zoom* | Mouse wheel zooms, dragging moves; this resets. |

Hover a piece of work or an arrow for its numbers (size, time in MPI, what HPX did).

In the two tree views the summary is short (messages, data, and the critical path when it is on): the split of the time
into waiting, HPX and MPI belongs to the lanes, and so does the colour legend below them.

### The 3D tree

<p align="center"><img src="../screenshots/3d_tree_send_recv_ratio.png" alt="3D tree" width="800"></p>

The same tree as in the flat view, laid out like the 3D cluster view of the EduMPI GUI: every **node** of the cluster is a pale glass
cube (the first node bottom left, then to the right and up, two columns), and the **localities** that run on it are small
numbered cubes inside it. The node of every locality comes from the run file (`locality_nodes` in its header, written by
`eduhpx-merge` from the node names in the MPI logs); for an older run file the localities are assumed to be spread evenly over the nodes (the names then say *assumed*).

**Lines.** Every message of the tree is drawn as two lines next to each other: a **green** line for the *send* (from the sender to the receiver) and a **red**
line for the *receive* (from the receiver to the sender it heard from, as in the EduMPI GUI). Thick lines are the data, thin lines the requests. The *Send* and *Recv*
buttons in the bar switch the two kinds on and off. With the *Critical path* button on, the lines of the path get a gold band and the others fade.

**Colours of the localities** (the selector in the bar; the scale next to it, and the (i), explain the colours):

| View | Colour |
|---|---|
| *send/recv ratio (per locality)* | green = it sent more data than it received, red = it received more, olive = about the same, white = no communication |
| *max send ratio (all localities)* | white to green: how much it sent, relative to the locality that sent the most in this group |
| *max recv ratio (all localities)* | white to red: how much it received, relative to the locality that received the most |
| *arrival of the data* | green = the data reached it first, red = last (for a reduce or gather: when it had the data of all its children) |

The numbers are the bytes of the messages of the group (data and requests); the formulas are those of the EduMPI GUI.

**Moving around.** Drag to turn the scene, wheel or pinch to zoom, double click to reset. Hover a line for its size, arrival time and whether
it stays inside a node or goes over the network. **Click a cube** to look at it: the camera flies to it, the cube gets a blue frame, only its lines stay bright, and a box shows what it sent
and received, when its data arrived, and its parent and children. Scroll out, click beside the cube, click it again, or press *Back to overview* to return.

<p align="center"><img src="../screenshots/3d_tree_focus_on_locality.png" alt="3D tree: one locality" width="800"></p>

The 3D view is loaded when you first open it. It needs Qt Quick 3D and a graphics driver that supports it; if that is missing, the other views work as usual.

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

The 3D tree (view `tree3d`) needs a real graphics window: leave out `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software` for it. A few environment
variables set it up for a preview: `EDUHPX_3D_MODE` (`ratio | send | recv | arrival`), `EDUHPX_3D_LINES` (`send` or `recv`: only these lines),
`EDUHPX_3D_SELECT=<locality>` (look at a cube), `EDUHPX_CRITICAL=1` (critical path on).
