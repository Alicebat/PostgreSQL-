#!/bin/bash
source /home/postgres/.bashrc
readonly cb_name=$1
readonly role=$2
readonly scope=$3
VIP=10.63.20.95
VIPBRD=10.63.23.255
VIPNETMASK=255.255.252.0
VIPNETMASKBIT=22
VIPDEV=team0
VIPLABEL=1

function usage() {
	echo "Usage: $0 <on_start|on_stop|on_role_change> <role> <scope>";
	exit 1;
}
function addvip(){
	echo "`date +%Y-%m-%d\ %H:%M:%S,%3N` INFO: /sbin/ip addr add ${VIP}/${VIPNETMASKBIT} brd ${VIPBRD} dev ${VIPDEV} label ${VIPDEV}:${VIPLABEL}"
	sudo /sbin/ip addr add ${VIP}/${VIPNETMASKBIT} brd ${VIPBRD} dev ${VIPDEV} label ${VIPDEV}:${VIPLABEL}
	sudo /usr/sbin/arping -q -A -c 1 -I ${VIPDEV} ${VIP}
}
function delvip(){
	echo "`date +%Y-%m-%d\ %H:%M:%S,%3N` INFO: sudo /sbin/ip addr del ${VIP}/${VIPNETMASKBIT} dev ${VIPDEV} label ${VIPDEV}:${VIPLABEL}"
	sudo /sbin/ip addr del ${VIP}/${VIPNETMASKBIT} dev ${VIPDEV} label ${VIPDEV}:${VIPLABEL}
}
echo "`date +%Y-%m-%d\ %H:%M:%S,%3N` WARNING: patroni callback $cb_name $role $scope"
case $cb_name in
	on_stop)
	      if [[ $role == 'master' ]]; then
			delvip
			fi
		;;
	on_start)
	      if [[ $role == 'master' ]]; then
			addvip
			fi
		;;
	on_role_change)
		if [[ $role == 'master' ]]; then
			addvip
		elif [[ $role == 'slave' ]]||[[ $role == 'replica' ]]||[[ $role == 'logical' ]]; then
			delvip
			fi
		;; 
	*)
		usage
		;;
esac
