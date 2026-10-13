#!/usr/bin/env bash
set -euo pipefail
PREFIX=gubaydullin-09

if yc load-balancer network-load-balancer get --name "$PREFIX-lb" >/dev/null 2>&1; then
 yc load-balancer network-load-balancer delete "$PREFIX-lb"
fi

if yc load-balancer target-group get --name "$PREFIX-tg" >/dev/null 2>&1; then
 yc load-balancer target-group delete "$PREFIX-tg"
fi

VM_NAMES=$(yc compute instance list --format json | jq -r --arg prefix "$PREFIX-" '.[] | select(.name | startswith($prefix)) | .name')
for name in $VM_NAMES; do
 yc compute instance delete "$name"
done

if yc vpc route-table get --name "$PREFIX-rt" >/dev/null 2>&1; then
 if yc vpc subnet get --name "$PREFIX-subnet-a" >/dev/null 2>&1; then
  yc vpc subnet update --name "$PREFIX-subnet-a" --disassociate-route-table
 fi
 yc vpc route-table delete "$PREFIX-rt"
fi

if yc vpc gateway get --name "$PREFIX-nat" >/dev/null 2>&1; then
 yc vpc gateway delete "$PREFIX-nat"
fi

if yc vpc subnet get --name "$PREFIX-subnet-a" >/dev/null 2>&1; then
 yc vpc subnet delete "$PREFIX-subnet-a"
fi

if yc vpc subnet get --name "$PREFIX-subnet-b" >/dev/null 2>&1; then
 yc vpc subnet delete "$PREFIX-subnet-b"
fi

if yc vpc network get --name "$PREFIX-net" >/dev/null 2>&1; then
 yc vpc network delete "$PREFIX-net"
fi
