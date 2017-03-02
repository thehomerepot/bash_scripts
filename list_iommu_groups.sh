#!/bin/sh

# List the devices in each IOMMU group, from AW at
# https://bbs.archlinux.org/viewtopic.php?id=162768&p=29

BASE="/sys/kernel/iommu_groups"

for i in $(find $BASE -maxdepth 1 -mindepth 1 -type d); do
	GROUP=$(basename $i)
	echo "### Group $GROUP ###"
	for j in $(find $i/devices -type l); do
		DEV=$(basename $j)
		echo -n "    "
		lspci -s $DEV
	done
done

