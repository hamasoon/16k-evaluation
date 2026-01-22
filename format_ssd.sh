#!/bin/bash

source ./find_ssd.sh
echo $SSD

sudo nvme format -f $SSD
