# hpx_collectives: the test program of the examples

One HPX collective, flat or hierarchical, repeated; the program behind `examples/`.

    COLL=bcast COLL_KIND=hier COLL_ITER=10 mpirun -np 16 ./hpx_collectives --hpx:ini=hpx.parcel.mpi.enable=1

`COLL`: bcast, reduce, allreduce, gather, allgather, scatter, alltoall, alltoall_large, scan_ex, scan_in, barrier.
`COLL_KIND`: flat or hier; `COLL_ARITY` (tree, default 2), `COLL_ITER` (default 10), `COLL_INTS` (payload, ints).
Build: `cmake -S . -B build -DHPX_DIR=<HPX>/lib64/cmake/HPX && cmake --build build`.
`run_examples.sbatch` runs all collectives for one size with `eduhpx-run` (Slurm; paths of our cluster, adapt them).
