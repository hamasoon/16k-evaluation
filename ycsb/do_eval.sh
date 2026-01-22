#!/bin/bash
set -euo pipefail

source ./find_ssd.sh

MOUNT_DIR="/mnt/nvme"
DB_DIR="${MOUNT_DIR}"
DB_SRC_DIR="/home/layfort/rocksdb"
TARGET="${1:-}"

get_cpus() {
	local node
	if [[ "$1" -eq 0 ]]; then
		node=0
	else
		node=1
	fi
	local exclude_cpus='^(32|33|34|35|36|37|38|39|40)$'
	lscpu -e=CPU,NODE | awk -v n="$node" '$2==n{print $1}' | grep -Ev "$exclude_cpus" | paste -sd,
}


YCSB_RUN_PROPERTIES="-p rocksdb.dir=${DB_DIR} \
                -p rocksdb.optionsfile=rocksdb-options_run.ini \
                -p maxexecutiontime=1800 \
                -p status.interval=1"

YCSB_LOAD_PROPERTIES="-p rocksdb.dir=${DB_DIR} \
                -p rocksdb.optionsfile=rocksdb-options_load.ini"

WORKLOADS=(
	"a"
	"b"
	"c"
	"d"
	"e"
	"f"
)

if [[ -z "$TARGET" || ! "$TARGET" =~ ^[0-3]$ ]]; then
	echo "usage: $0 <TARGET: 0|1|2|3>" >&2
	exit 1
fi

if [[ "$TARGET" -eq 0 ]]; then
	SSD="${SSD}p1"
else
	SSD="/dev/nvme4n1"
fi

echo "Running evaluation with TARGET=${TARGET} on SSD=${SSD}"

mkdir -p output
sudo chown -R "$(whoami):$(whoami)" output

sudo umount "$MOUNT_DIR" || true

for w in "${WORKLOADS[@]}"; do
	workload_path="workloads/workload${w}"
	output_path="output/${w}"
	mkdir -p "$output_path"

	if [[ ! -f "$workload_path" ]]; then
 		echo "missing workload file: $workload_path" >&2
 		exit 1
	fi

	if [[ $TARGET -ne 0 ]]; then
		echo "Loading nvmev kernel module..."
		if grep -q '^nvmev ' /proc/modules; then
			sudo rmmod nvmev
		fi

		MAPPING=""

		case "$TARGET" in
			1) MAPPING="16k";;
			2) MAPPING="4k";;
			3) MAPPING="32k";;
		esac

		sudo insmod ./nvmev_${MAPPING}.ko \
		memmap_start=256G \
		memmap_size=128G \
		dispatcher_cpus=32,33,34,35 \
		worker_cpus=36,37,38,39 \
		intr_cpu=40
	else
		./format_ssd.sh
	fi
	
    rm -rf "${DB_DIR}"
    mkdir -p "${DB_DIR}"

	sudo mkfs.ext4 -F "$SSD"
	sudo mount -o nobarrier "$SSD" "$MOUNT_DIR"
    sudo chown "$(whoami):$(whoami)" ${DB_DIR}
    rsync -av ${DB_SRC_DIR} ${DB_DIR}	

    mkdir -p $output_path

	case "$TARGET" in
 		0) tag="BM1743" ;;
 		1) tag="virt-16k" ;;
 		2) tag="virt-4k" ;;
 		3) tag="virt-32k" ;;
	esac

	echo "laod ${w} in ${tag}"

	sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"

	if [[ $TARGET -ne 0 ]]; then
		sudo sh -c "echo 0 > /proc/nvmev/buffer"
	fi

	sudo numactl --physcpubind=$(get_cpus $TARGET) python2 ./bin/ycsb  load rocksdb -s -P $workload_path ${YCSB_LOAD_PROPERTIES} 2>&1 | tee ${output_path}/${tag}_load.log
	
	sudo chown "$(whoami):$(whoami)" "${output_path}/${tag}_load.log"

	if [[ $TARGET -ne 0 ]]; then
		sudo cat /proc/nvmev/buffer >> "${output_path}/${tag}_load.log"
		sudo dmesg | tail -n 20 >> "${output_path}/${tag}_load.log"
	fi

	sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"

	if [[ $TARGET -ne 0 ]]; then
		sudo sh -c "echo 0 > /proc/nvmev/buffer"
	fi

	sleep 600

	sudo numactl --physcpubind=$(get_cpus $TARGET) python2 ./bin/ycsb run rocksdb -s -P $workload_path ${YCSB_RUN_PROPERTIES} 2>&1 | tee ${output_path}/${tag}_run.log

	sudo chown "$(whoami):$(whoami)" "${output_path}/${tag}_run.log"

	if [[ $TARGET -ne 0 ]]; then
		sudo cat /proc/nvmev/buffer >> "${output_path}/${tag}_run.log"
		sudo dmesg | tail -n 20 >> "${output_path}/${tag}_run.log"
	fi
	
	sudo umount "$MOUNT_DIR" || true

	sleep 600
done

