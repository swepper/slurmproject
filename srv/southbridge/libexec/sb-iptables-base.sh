#!/bin/bash
# THIS FILE IS MANAGED BY ANSIBLE, ALL CHANGES WILL BE LOST
#
# Run script for sb-iptables-base.service
# Southbridge LLC, 2017 A. D.

set -o nounset
set -E

readonly PATH=/bin:/sbin:/usr/bin:/usr/sbin
readonly bn=$(basename $0)

# Configuration
readonly dstports_tcp="111,2812,48022,10050,5900:5910"
readonly dstports_udp="111,123,161"
readonly whitelist="/srv/southbridge/etc/sb-iptables-base.conf"
readonly chain="SB.base"
readonly w="--wait"

trap except ERR

start() {
    local FN=$FUNCNAME

    if iptables-save | fgrep -q ":$chain"; then
        return
    else
        iptables $w -N $chain
        reload
    fi
}

reload() {
    local FN=$FUNCNAME

    if [[ ! -f "$whitelist" ]]; then
        echo "${bn}: main configuration file is missing" 1>&2
        false
    fi

    if ! iptables-save | fgrep -q ":$chain"; then
        echo "${bn}: chain '$chain' not found" 1>&2
        false
    fi

    iptables $w -F $chain
    iptables $w -A $chain -m addrtype --src-type LOCAL -j ACCEPT

    for src in $(egrep -v '^#|^$|^\s+$' $whitelist | awk '{ print $1 }' | sort | uniq); do
        iptables $w -A $chain -s $src -j ACCEPT
    done

    iptables $w -A $chain -j REJECT --reject-with icmp-host-prohibited
    removejump
    iptables $w -I INPUT $(find_insert_position) -p tcp -m multiport --dports $dstports_tcp -j $chain
    iptables $w -I INPUT $(find_insert_position) -p udp -m multiport --dports $dstports_udp -j $chain
}

removejump() {
    iptables-save | awk -v chain="-j $chain" '$0 ~ chain { sub(/-A/, "-D"); system("iptables --wait "$0) }'
}

# Если есть правило с ESTABLISHED - то вставляем после него, если нет - в начало
find_insert_position() {
    local FN=$FUNCNAME
    local -i pos=0

    pos=$(iptables-save -t filter | fgrep -- '-A INPUT' | awk '/ESTABLISHED/ { print NR + 1; exit }')

    if (( pos )); then
        printf "%i" $pos
    else
        printf "%i" 1
    fi
}

stop() {
    removejump
    iptables $w -F $chain 2>/dev/null || true
    iptables $w -X $chain 2>/dev/null || true
}

status() {
    local FN=$FUNCNAME

    if iptables-save | fgrep -q ":$chain"; then
        iptables $w -t filter -n -v -L $chain
    else
        echo "${bn}: chain '$chain' not found" 1>&2
        exit 1
    fi
}

except() {
    local RET=$?

    stop
    echo "ERROR: service $bn failed in function '$FN'" 1>&2
    exit $RET
}

usage() {
    echo "Usage: $bn start | stop | reload | restart | status"
}

case "${1:-NOP}" in
    start) start
        ;;
    stop) stop
        ;;
    reload) reload
        ;;
    restart) stop; start
        ;;
    status) status
        ;;
    *) usage
esac

exit 0

