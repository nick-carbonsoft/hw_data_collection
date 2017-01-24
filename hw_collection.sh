#!/bin/bash

write_to_file() {
    local description="$1"
    local value="$2"
    local equipment="/tmp/equipment"
    echo "$description:$value" >> "$equipment"
}

find_params_mem() {
    local value="$1"
    local mem_info="/proc/meminfo"
    # 1. Ищем значение $value в mem_info
    # 2. Выводим 2 столбец после ":"
    # 3. Удаляем табуляцию и пробелы
    # 4. Выводим первый столбец, т.е целое число
    grep -i "$value" "$mem_info" | awk -F: '{print $2}' | sed 's/^[ \t]*//' | cut -d' ' -f1
}

mem_params() {
    local mem_total
    mem_total="$(find_params_mem "MemTotal")"
    mem_free="$(find_params_mem "MemFree")"
    printf '"RAM": [
    {
        "total":"%s",
        "free":"%s"
    }
    ]\n' "$mem_total" "$mem_free"
}

find_params_cpu() {
    local pattern="$1"
    local cpu="/tmp/cpu"
    lscpu > "$cpu"
    # 1. Ищем значение $pattern в lscpu
    # 2. Выводим 2 столбец после ":"
    # 3. Удаляем табуляцию и пробелы
    # 4. Удаляем больше 2 идущих подряд пробелов
    grep -i "$pattern" "$cpu" | awk -F: '{print $2}' | sed 's/^[ \t]*//' | tr -s " "
}

cpu_params() {
    local number_proc_core vendor model l3_cache mem_total freq ht l2_cache l3_cache virtualization

    number_proc_core="$(nproc)"
    vendor="$(find_params_cpu "Vendor ID")"
    model="$(grep 'model name' /proc/cpuinfo | sort -u | awk -F: '{print $2}' | sed 's/^[ \t]*//' | tr -s " ")"
    freq="$(find_params_cpu "CPU MHz")"

    ht="$(find_params_cpu "Thread")"
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

iface_params() {
    local key="$1"
    local device="$2"
    local pattern="$3"
    ethtool $key "$device" | grep -i "$pattern" | awk -F: '{print $2}' | sed 's/^[ \t]*//'
}

collect_buffers() {
    tac | egrep -o [0-9]+ | tr '\n' '/'| sed 's|/$||g'
}

gen_iface_params() {
    local iface="$1"
    local queue_count
    local LSPCI="/tmp/lspci.tmp"
    lspci > "$LSPCI"

    for id in $(ethtool -i $iface | grep bus-info | sed 's/.*0000://'); do
        product_name="$(grep -w $id $LSPCI | cut -d: -f3 | sed 's/^[ \t]*//')"
    done
    # TODO: выводить для каждого интерфейса
    driver="$(iface_params -i "${iface%:}" "driver")"
    speed="$(iface_params " " "${iface%:}" "speed")"
    rx_buffer="$(iface_params -g "${iface%:}" "RX:" | collect_buffers)"
    tx_buffer="$(iface_params -g "${iface%:}" "TX:" | collect_buffers))"
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

rom_params() {
    local vendor
    local disk_type
    local model
    local rom_desc

    # TODO: Сделать проверку для всех жестких дисков
    rom_desc="$(cat /proc/scsi/scsi | egrep -v "CDDVDW|CD-ROM|DVD-ROM|File-CD" | grep "Model" | head -1)"
    disk_type="$(cat /sys/block/sda/queue/rotational)"
    vendor="$(echo $rom_desc | grep -o -P '(?<=Vendor:).*(?=Model)' | sed 's/^[ ]*//' | sed 's/[ \t]*$//')"
    model="$(echo "$rom_desc" | grep -o -P '(?<=Model:).*(?=Rev:)' | sed 's/^[ ]*//' | sed 's/[ \t]*$//')"

    if [ $disk_type = "1" ];then
        disk_type="HDD"
    else
        disk_type="SSD"
    fi
    printf '"ROM: [
    {
        "vendor":"%s",
        "model":"%s"
        "type":"%s",
    }
    ]\n' "$vendor" "$model" "$disk_type"
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
    echo "{"
    cpu_params
    mem_params
    info_iface
    rom_params
    echo "}"
}

main
