#!/usr/bin/env bash
#SBATCH -p vip
#SBATCH --exclusive
#SBATCH -o $HOME/eduhpx_examples/matrix-%x-%j.log
# every collective, flat and hierarchical, for one size (nodes x localities per node); one run.csv each
# usage: sbatch -N <nodes> --ntasks-per-node=<ppn> --job-name=m<nodes>x<ppn> matrix.sbatch   (env ITER=10 COLLS="..." KINDS="flat hier")
ITER=${ITER:-10}; COLLS=${COLLS:-"bcast reduce allreduce gather allgather scatter alltoall alltoall_large scan_ex scan_in barrier"}; KINDS=${KINDS:-"flat hier"}
N=$SLURM_JOB_NUM_NODES; PPN=$SLURM_NTASKS_PER_NODE; LOC=$SLURM_NTASKS; PE=$((60 / PPN))
export PMIX_MCA_pcompress_base_silence_warning=1
S=$HOME/eduhpx_e2e/scripts; OUTD=$HOME/eduhpx_examples; RAW=$OUTD/raw; mkdir -p $RAW
CLK=
for c in $COLLS; do for k in $KINDS; do
  case $c in bcast) INTS=16384;; alltoall_large) INTS=2048;; *) INTS=1024;; esac
  NAME=${c}_${k}_${LOC}loc_${N}nodes; D=$RAW/${NAME}_$SLURM_JOB_ID
  export COLL=$c COLL_KIND=$k COLL_ITER=$ITER COLL_INTS=$INTS COLL_ARITY=2
  echo "[$(date +%H:%M:%S)] $NAME"
  timeout 240 $S/eduhpx-run --mpi $HOME/eduhpx_mpi --hpx $HOME/eduhpx_hpx --out $D --name $NAME --only-collectives ${CLK:+--clock-file $CLK} -- \
    mpirun --map-by ppr:$PPN:node:PE=$PE --bind-to core -n $LOC -x COLL -x COLL_KIND -x COLL_ITER -x COLL_INTS -x COLL_ARITY -x PMIX_MCA_pcompress_base_silence_warning \
    $HOME/hpx_collectives/hpx_collectives --hpx:threads=4 --hpx:bind=none --hpx:run-hpx-main --hpx:ini=hpx.parcel.tcp.enable=0 --hpx:ini=hpx.parcel.mpi.enable=1 < /dev/null > $D.out 2>&1
  rc=$?
  [ -f $D/run.csv ] && cp $D/run.csv $OUTD/$NAME.csv
  [ -z "$CLK" ] && [ -f $D/clock_offsets.csv ] && CLK=$D/clock_offsets.csv
  echo "   exit $rc, $(grep -c . $OUTD/$NAME.csv 2>/dev/null || echo no-csv) lines, $(grep -h "^groups:" $D.out | head -1 | cut -c1-120)"
done; done
echo ALL_DONE
