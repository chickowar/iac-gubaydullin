#!/usr/bin/env bash
set -euo pipefail

PREFIX=gubaydullin-09

delete_if_exists() { # функция, чтобы удалять только если такой ресурс есть
  local NAME="$1"
  shift # first parameter out of the question now
  # $@ are the rest of parameters put into command line
  local ID
  ID=$(yc "$@" list --format json |
    jq -r --arg name "$NAME" \
      '.[] | select(.name == $name) | .id')

  if [[ -n "$ID" ]]; then
    yc "$@" delete "$ID"
  fi
}

# Удаляем балансировщик и целевую группу
delete_if_exists "$PREFIX-lb" load-balancer network-load-balancer
delete_if_exists "$PREFIX-tg" load-balancer target-group

# Удаляем все существующие ВМ с началом gubaydullin-09-app-
VM_IDS=$(yc compute instance list --format json |
  jq -r --arg prefix "$PREFIX-app-" \
    '.[] | select(.name | startswith($prefix)) | .id')
for id in $VM_IDS; do
  yc compute instance delete "$id"
done

# Удаляем диск, подсети и сеть
delete_if_exists "$PREFIX-data" compute disk
delete_if_exists "$PREFIX-subnet-a" vpc subnet
delete_if_exists "$PREFIX-subnet-b" vpc subnet
delete_if_exists "$PREFIX-net" vpc network
