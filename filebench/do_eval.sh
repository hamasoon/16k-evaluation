#!/bin/bash
set -euo pipefail

source ./find_ssd.sh

MOUNT_DIR="/mnt/nvme"
TARGET="${1:-}"

NODE=1
EXCLUDE_CPUS='^(32|33|34|35|36|37|38|39|40)$'
CPUS=$(lscpu -e=CPU,NODE | awk -v n="$NODE" '$2==n{print $1}' | grep -Ev "$EXCLUDE_CPUS" | paste -sd,)

WORKLOADS=(
	"webserver.f"
	"fileserver.f"
	"varmail.f"
	"oltp.f"
	"webproxy.f"
	"mongo.f"
	"createfiles.f"
	"makedirs.f"
	"randomwrite.f"
	"randomread.f"
	"randomrw.f"
)

if [[ -z "$TARGET" || ! "$TARGET" =~ ^[0-3]$ ]]; then
	echo "usage: $0 <TARGET: 0|1|2|3>" >&2
	exit 1
fi

if [[ "$TARGET" -eq 0 ]]; then
	SSD="/dev/nvme2n1"
	# SSD="${SSD}p1"
else
	SSD="/dev/nvme4n1"
fi

echo "Running evaluation with TARGET=${TARGET} on SSD=${SSD}"

sudo sh -c "echo 0 > /proc/sys/kernel/randomize_va_space"
mkdir -p output
sudo chown -R "$(whoami):$(whoami)" output

sudo umount "$MOUNT_DIR" || true

for w in "${WORKLOADS[@]}"; do
	workload_path="workloads/${w}"
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
		sudo insmod ./nvmev.ko \
		memmap_start=256G \
		memmap_size=128G \
		dispatcher_cpus=32,33,34,35 \
		worker_cpus=36,37,38,39 \
		intr_cpu=40
	else
		./format_ssd.sh
	fi

	sudo mkfs.ext4 -F "$SSD"
	sudo mount "$SSD" "$MOUNT_DIR"
	sudo chown "$(whoami):$(whoami)" ${MOUNT_DIR}

	case "$TARGET" in
 		0) tag="FADU_dummy" ;;
 		1) tag="virt-16k_dummy" ;;
 		2) tag="virt-4k" ;;
 		3) tag="virt-32k" ;;
	esac

	echo "run ${w} in ${tag}"
	sudo numactl --physcpubind=$CPUS filebench -f "$workload_path" 2>&1 | sudo tee "${output_path}/${tag}.log" > /dev/null

	sudo chown "$(whoami):$(whoami)" "${output_path}/${tag}.log"

	if [[ $TARGET -ne 0 ]]; then
		sudo cat /proc/nvmev/buffer >> "${output_path}/${tag}.log"
		sudo dmesg | tail -n 20 >> "${output_path}/${tag}.log"
	fi
	
	sudo umount "$MOUNT_DIR" || true
done
