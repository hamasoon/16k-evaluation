#!/bin/bash
DEV="nvme1n1"
MNT_PATH="/mnt/nvme"
DB_PATH="${MNT_PATH}/db"
DB_SRC_PATH="/home/bae/rocksdb/"
OUTDIR="/home/bae/16K_data/ycsb"

YCSB_RUN_PROPERTIES="-p rocksdb.dir=${DB_PATH} \
                -p threadcount=16 \
                -p rocksdb.optionsfile=rocksdb-options_run.ini \
                -p maxexecutiontime=1800 \
                -p status.interval=1"

YCSB_LOAD_PROPERTIES="-p rocksdb.dir=${DB_PATH} \
                -p rocksdb.optionsfile=rocksdb-options_load.ini"

WORKLOADS_A2F=("workloada" "workloadb" "workloadc" "workloadf")
WORKLOADS_DE=("workloadd" "workloade")

function do_init() {
    local workload=$1
    local logdir=$OUTDIR/$workload/bm1743_full_load.log

    sudo umount ${MNT_PATH}
    sudo mkfs.ext4 -F /dev/${DEV}
    sudo mount /dev/${DEV} ${MNT_PATH}
    rm -rf "${DB_PATH}"
    mkdir -p "${DB_PATH}"
    sudo chown bae:bae ${DB_PATH}
    rsync -av ${DB_SRC_PATH} ${DB_PATH}

    mkdir -p $OUTDIR/$workload

    sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
    sudo sh -c "echo 0 > /proc/nvmev/buffer"
    sudo sh -c "echo '' > $logdir"

    python2 ./bin/ycsb load rocksdb -s -P workloads/$workload ${YCSB_LOAD_PROPERTIES} 2>&1 | tee $logdir

    sudo cat /proc/nvmev/buffer >> $logdir
}

function do_test() {
    local workload=$1
    local logdir=$OUTDIR/$workload/bm1743_full_test.log

    mkdir -p $OUTDIR/$workload

    sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
    sudo sh -c "echo 0 > /proc/nvmev/buffer"
    sudo sh -c "echo '' > $logdir"

    python2 ./bin/ycsb run rocksdb -s -P workloads/$workload ${YCSB_RUN_PROPERTIES} 2>&1 | tee $logdir

    sudo cat /proc/nvmev/buffer >> $logdir
}

mkdir -p $OUTDIR

do_init "workloada"

for wl in "${WORKLOADS_A2F[@]}"; do
    do_test $wl
done

for wl in "${WORKLOADS_DE[@]}"; do
    do_init $wl
    do_test $wl
done
