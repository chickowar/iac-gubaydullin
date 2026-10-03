#!/usr/bin/env bash
set -euo pipefail

export PREFIX="gubaydullin-09"

yc compute instance delete "$PREFIX-app-1"
yc compute instance delete "$PREFIX-app-2"
yc vpc subnet delete "$PREFIX-subnet"
yc vpc network delete "$PREFIX-net"

# Проверяем оставшиеся ресурсы
yc compute instance list
yc compute disk list
yc vpc subnet list
yc vpc network list
