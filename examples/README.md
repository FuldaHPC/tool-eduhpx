# Example run files

All of them are built into the viewer: the start screen lists them, and *File > Examples...* opens the same list.
Or open a file from this folder with *Open run...*.

## The collectives

Every HPX collective, once flat (all localities talk to one root) and once as a tree (`create_hierarchical_communicator`,
arity 2), each on 16 localities (4 nodes), 32 localities (4 nodes) and, except all-to-all, 64 localities (8 nodes).
File name: `<collective>_<flat|hier>_<localities>loc_<nodes>nodes.csv`.

| Collective | In the tree variant (as seen in the runs) |
|---|---|
| `bcast` Broadcast | every node asks its parent, data moves down |
| `reduce`, `gather` | values move up the tree |
| `scatter` | blocks move down the tree |
| `allreduce` | a reduce up, then a broadcast down |
| `allgather` | a gather up, then a broadcast down |
| `alltoall`, `alltoall_large` (8 KiB per pair) | all-to-all together with a gather and a scatter |
| `scan_ex`, `scan_in` (exclusive / inclusive scan) | a gather and a scatter |
| `barrier` | the barrier of HPX, flat or as a tree |

`mixed_4loc_1node.csv` is ordinary point-to-point traffic without a collective (an older run of the first prototype).

## How they were made

`eduhpx-run ... --only-collectives` with the test program `tools/hpx_collectives` of the project (HPX master `e65a7a3`, the
measuring MPI on Open MPI 5.0.11rc1, UCX, 4 threads per locality, one run each). Broadcast: 64 KiB, other collectives about
4 KiB per locality, 10 repetitions (5 with 64 localities). The start-up and shutdown traffic of HPX is left out; the four
barriers that HPX itself runs at the start and the end remain as groups.

## What to keep in mind

- **One run each, on one cluster.** They show what the communication looks like, not how fast a collective is.
- **"HPX prepares" can be waiting.** A parcel whose data is not ready yet (the answer of a collective that waits for the
  last locality) is created early and sent late; the parcel log has no time for "the data became ready", so that waiting
  is drawn as *HPX prepares* (for example the long bars at the root of a flat all-to-all). The tree view of a broadcast
  separates it as *waits for data*.
- **A few parcels have no MPI data** (2 % without a matching MPI receive, 0.3 % without a send). They are counted in the
  title but not drawn. Parcels with several zero-copy chunks, and the small internal messages of barriers and scans, are the
  most likely to be affected.
