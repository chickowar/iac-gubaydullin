#!/usr/bin/env bash
set -euo pipefail

# ---- параметры варианта ----
PREFIX=gubaydullin-09
ZONE_A=ru-central1-d
ZONE_B=ru-central1-a
CIDR_A=10.19.1.0/24
CIDR_B=10.19.2.0/24
APP_PORT=8027
GREETING=cloudlab

WEB_COUNT="${WEB_COUNT:-2}"
while [ "$#" -gt 0 ]; do
 case "$1" in
  --web-count)
   WEB_COUNT="$2"
   shift 2
   ;;
  *)
   echo "Неизвестный аргумент: $1" >&2
   exit 1
   ;;
 esac
done

BOOT_SIZE=25
IMAGE_FAMILY=ubuntu-2404-lts

echo "==> сеть и подсети"

if yc vpc network get "$PREFIX-net" >/dev/null 2>&1; then
 echo "сеть $PREFIX-net уже есть, пропускаю"
else
 yc vpc network create --name "$PREFIX-net"
fi

if yc vpc subnet get "$PREFIX-subnet-a" >/dev/null 2>&1; then
 echo "подсеть $PREFIX-subnet-a уже есть, пропускаю"
else
 yc vpc subnet create --name "$PREFIX-subnet-a" --network-name "$PREFIX-net" \
  --zone "$ZONE_A" --range "$CIDR_A"
fi

if yc vpc subnet get "$PREFIX-subnet-b" >/dev/null 2>&1; then
 echo "подсеть $PREFIX-subnet-b уже есть, пропускаю"
else
 yc vpc subnet create --name "$PREFIX-subnet-b" --network-name "$PREFIX-net" \
  --zone "$ZONE_B" --range "$CIDR_B"
fi

echo "==> NAT-шлюз"
if yc vpc gateway get --name "$PREFIX-nat" >/dev/null 2>&1; then
 echo "NAT-шлюз $PREFIX-nat уже есть, пропускаю"
else
 yc vpc gateway create --name "$PREFIX-nat"
fi

GW_ID=$(yc vpc gateway get --name "$PREFIX-nat" --format json | jq -r .id)
if yc vpc route-table get --name "$PREFIX-rt" >/dev/null 2>&1; then
 echo "таблица маршрутизации $PREFIX-rt уже есть, пропускаю"
else
 yc vpc route-table create --name "$PREFIX-rt" --network-name "$PREFIX-net" \
  --route "destination=0.0.0.0/0,gateway-id=$GW_ID"
fi
yc vpc subnet update --name "$PREFIX-subnet-a" --route-table-name "$PREFIX-rt"

echo "==> файл настройки из шаблона"
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export APP_PORT GREETING SSH_KEY
# shellcheck disable=SC2016
envsubst '${APP_PORT} ${GREETING} ${SSH_KEY}' \
  < hw-01/cloud-init.tpl.yaml > hw-01/cloud-init.yaml

echo "==> машины"
ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$PREFIX-subnet-a" "$PREFIX-subnet-b")

for i in $(seq 1 "$WEB_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  if yc compute instance get "$PREFIX-web-$i" >/dev/null 2>&1; then
    echo "машина $PREFIX-web-$i уже есть, пропускаю"
  else
    yc compute instance create \
      --name "$PREFIX-web-$i" \
      --zone "${ZONES[$idx]}" \
      --platform standard-v3 \
      --cores=2 --core-fraction=20 --memory=2 \
      --preemptible \
      --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
      --network-interface subnet-name="${SUBNETS[$idx]}",nat-ip-version=ipv4 \
      --hostname "$PREFIX-web-$i" \
      --metadata-from-file user-data=hw-01/cloud-init.yaml
  fi
done

echo "==> сервер приложения"

if yc compute instance get "$PREFIX-app-1" >/dev/null 2>&1; then
 echo "машина $PREFIX-app-1 уже есть, пропускаю"
else
 yc compute instance create \
  --name "$PREFIX-app-1" \
  --zone "$ZONE_A" \
  --platform standard-v3 \
  --cores=2 --core-fraction=20 --memory=2 \
  --preemptible \
  --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
  --network-interface subnet-name="$PREFIX-subnet-a" \
  --hostname "$PREFIX-app-1" \
  --metadata-from-file user-data=hw-01/cloud-init.yaml
fi

echo "==> целевая группа"

if yc load-balancer target-group get --name "$PREFIX-tg" >/dev/null 2>&1; then
 echo "целевая группа $PREFIX-tg уже есть, пропускаю"
else
 TARGETS=""
 for i in $(seq 1 "$WEB_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  IP=$(yc compute instance get "$PREFIX-web-$i" --format json \
  | jq -r '.network_interfaces[0].primary_v4_address.address')
  TARGETS="$TARGETS --target subnet-name=${SUBNETS[$idx]},address=$IP"
 done
 yc load-balancer target-group create --name "$PREFIX-tg" "${TARGETS[@]}"
fi

echo "==> балансировщик"
# идентификатор целевой группы: балансировщик ссылается на неё по нему
if yc load-balancer network-load-balancer get --name "$PREFIX-lb" >/dev/null 2>&1; then
  echo "балансировщик $PREFIX-lb уже есть, пропускаю"
else
  TG_ID=$(yc load-balancer target-group get --name "$PREFIX-tg" --format json | jq -r .id)
  yc load-balancer network-load-balancer create \
    --name "$PREFIX-lb" \
    --region-id ru-central1 \
    --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
    --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/
fi
