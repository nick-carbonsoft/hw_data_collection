#!/bin/bash

cpu="/tmp/cpu"
equipment="/tmp/equipment"
LSPCI="/tmp/lspci.tmp"
lscpu > "$cpu"
lspci > "$LSPCI"


write_to_file() {
	local description="$1"
	local value="$2"
	echo "$description:$value" >> "$equipment"
}

find_params_cpu() {
	local pattern="$1"
	grep "$pattern" "$cpu" | awk -F: '{print $2}' | sed 's/^[ \t]*//' | tr -s " "
}

mem_params() {
	local mem_total
	mem_total="$(cat /proc/meminfo | grep 'MemTotal' | awk -F: '{print $2}' | sed 's/^[ \t]*//' | cut -d' ' -f1)"
	mem_free="$(cat /proc/meminfo | grep 'MemFree' | awk -F: '{print $2}' | sed 's/^[ \t]*//' | cut -d' ' -f1)"
	printf '"RAM": [
	{"total":"%s",
	"free":"%s"}
	]\n' "$mem_total" "$mem_free"
}

cpu_params() {
	local number_proc_core vendor model l3_cache mem_total freq ht l2_cache l3_cache

	number_proc_core="$(nproc)"
	vendor="$(find_params_cpu "Vendor ID")"
	model="$(find_params_cpu "Model name")"
	freq="$(find_params_cpu "CPU MHz")"

	ht="$(grep "Thread" "$cpu" | egrep -o [0-9]+)"
	[[ "$ht" == "1" ]] && ht="0"
	l1d_cache="$(find_params_cpu "L1d cache")"
	l1i_cache="$(find_params_cpu "L1i cache")"
	l2_cache="$(find_params_cpu "L2 cache")"
	l3_cache="$(find_params_cpu "L3 cache")"

	printf '"processor": [
	{
    "CPU":"%s",
	"model":"%s",
	"vendor":"%s",
	"frequency":"%s",
	"hyper_threading":"%s",
	"L1d":"%s",
    "L1i":"%s",
	"L2":"%s",
    "L3":"%s"
    }
	]\n' "$number_proc_core" "$model" "$vendor" "$freq" \
		"$ht" "$l1d_cache" "$l1i_cache" \
		"$l2_cache" "$l3_cache"

}

gen_iface_params() {
	local iface="$1"
	local queue_count

	for id in $(ethtool -i $iface | grep bus-info | sed 's/.*0000://'); do
		product_name="$(grep -w $id $LSPCI | cut -d: -f3 | sed 's/^[ \t]*//')"
	done
	driver="$(ethtool -i "${iface%:}" | grep driver | awk '{print $2}')"
	speed="$(ethtool "${iface%:}" | grep -i speed | awk -F: '{print $2}' | sed 's/^[ \t]*//')"
	rx_buffer="$(ethtool -g "${iface%:}" | tac | grep RX: | egrep -o [0-9]+ | tr '\n' '/'| sed 's|/$||g')"
	tx_buffer="$(ethtool -g "${iface%:}" |  tac | grep TX: | egrep -o [0-9]+ | tr '\n' '/'| sed 's|/$||g')"
	queue_count="$(ls -1 /sys/class/net/"${iface%:}"/queues/ | grep "rx" | wc -l)"

	printf '"interfaces": [
	{
    "iface":"%s",
	"product_name":"%s",
	"driver":"%s",
	"queue_count":"%s",
	"speed":"%s",
	"rx_buffer":"%s",
	"tx_buffer":"%s"
    }
	]\n' "$iface" "$product_name" "$driver" "$queue_count" "$speed" "$rx_buffer" \
		"$tx_buffer"
}

virt_info() {
	local virt="QEMU VBOX"
    status="$(cat /proc/scsi/scsi | grep -v "CDDVDW" | grep -o -P '(?<=Vendor:).*(?=Model)' | sed 's/^[ ]*//' | sed 's/[ \t]*$//')"
	#for vm in $virt; do
	#	cat /proc/scsi/scsi | grep Vendor | grep "$vm" || continue
	#	if [ "$?" = 0 ]; then
	#		echo 
	#	fi
	#done
    printf '"machine:
    {
    "Vendor":"%s"
    }\n' "$status"

}

info_iface() {
	local tmpfile="/tmp/iface.list"

	name="$(lspci | grep Ethernet | awk -F: '{print $3}' | sed 's/^[ \t]*//' | sort -u)"
	def_route="$(ip r | grep -m1 default | egrep -o [a-z]+[0-9]+)"
	ip -o l | egrep ": (eth|em|en|bond)" | grep -v "@" | grep -vw "${def_route// /}" > "$tmpfile"
	while read _ iface _; do
		gen_iface_params "$iface"
	done < "$tmpfile"
	write_to_file "name" "$name"


	rm -f "$tmpfile"
}

main() {
	rm -f "$equipment"
	echo -e "{"
	cpu_params
	mem_params
	info_iface
    virt_info
	echo -e "}"
}

main
