#!/bin/bash
OUTDIR="/home/bae/16K_data/filebench"
TARGET="/mnt/nvme"
DEV=nvme1n1p1

WORKLOADS=(
    "createfiles"
    "fileserver"
    "makedirs"
    "mongo"
    "oltp"
    "randomread"
    "randomrw"
    "randomwrite"
    "varmail"
    "videoserver"
    "webproxy"
    "webserver"
)

function do_init() {
	sudo sh -c "echo 0 > /proc/sys/kernel/randomize_va_space"

	sudo umount $TARGET
	sudo mkfs.ext4 -F /dev/$DEV || exit
	sudo mount /dev/$DEV $TARGET || exit
}

function do_test() {
    local workload=$1
    local logdir=$OUTDIR/$workload/bm1743_parted.log

    mkdir -p $OUTDIR/$workload

    sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
    sudo sh -c "echo 0 > /proc/nvmev/buffer"
    sudo sh -c "echo '' > $logdir"

	sudo filebench -f /home/bae/filebench/workloads/$1.f 2>&1 | tee $logdir

    sudo cat /proc/nvmev/buffer >> $logdir
}

mkdir -p $OUTDIR

for wl in "${WORKLOADS[@]}"; do
	do_init
	do_test $wl $dev
done
