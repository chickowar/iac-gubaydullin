#!/usr/bin/env bash
set -euo pipefail            # стоп на первой ошибке и на пустой переменной

# ---- параметры варианта ----
PREFIX=gubaydullin-09        # префикс имён ресурсов
ZONE_A=ru-central1-d         # зона A
ZONE_B=ru-central1-a         # зона B
CIDR_A=10.19.1.0/24          # подсеть в зоне A
CIDR_B=10.19.2.0/24          # подсеть в зоне B
APP_PORT=8027                # порт, на котором отвечает nginx
GREETING=cloudlab            # слово из варианта, оно же на странице
VM_COUNT="${1:-2}"           # число машин в группе (по умолчанию как в варианте, но можно задать из консоли)
DISK_SIZE="${2:-15}"         # дополнительный диск, ГБ — из варианта (также можно задать в консоли)
BOOT_SIZE=25                 # загрузочный диск, ГБ — из варианта
IMAGE_FAMILY=ubuntu-2404-lts # образ машин, одинаковый у всех вариантов


# Сеть и подсеть
echo "==> сеть и подсети"
yc vpc network create --name "$PREFIX-net"

yc vpc subnet create --name "$PREFIX-subnet-a" --network-name "$PREFIX-net" \
  --zone "$ZONE_A" --range "$CIDR_A"
yc vpc subnet create --name "$PREFIX-subnet-b" --network-name "$PREFIX-net" \
  --zone "$ZONE_B" --range "$CIDR_B"


# создание cloud-init.yaml
echo "==> файл настройки из шаблона"
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export APP_PORT GREETING SSH_KEY
envsubst '${APP_PORT} ${GREETING} ${SSH_KEY}' \
  < work-02/cloud-init.tpl.yaml > work-02/cloud-init.yaml


# Развёртывание ВМ и создание диска
echo "==> дополнительный диск"
yc compute disk create --name "$PREFIX-data" --zone "$ZONE_A" \
  --size "$DISK_SIZE" --type network-hdd

echo "==> машины"
ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$PREFIX-subnet-a" "$PREFIX-subnet-b")

for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  DISK_ATTACH_LINE=()
  if (( i==1 )); then
    DISK_ATTACH_LINE=(
      --attach-disk
      "disk-name=$PREFIX-data,device-name=data,auto-delete=false"
    )
  fi

  # if app-1, then attach a disk
  yc compute instance create \
    --name "$PREFIX-app-$i" \
    --zone "${ZONES[$idx]}" \
    --platform standard-v3 \
    --cores=2 --core-fraction=20 --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
    --network-interface subnet-name="${SUBNETS[$idx]}",nat-ip-version=ipv4 \
    --hostname "$PREFIX-app-$i" \
    "${DISK_ATTACH_LINE[@]}" \
    --metadata-from-file user-data=work-02/cloud-init.yaml
done




# Заводим балансировщик
echo "==> целевая группа"
TARGETS=""

for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  IP=$(yc compute instance get "$PREFIX-app-$i" --format json \
    | jq -r '.network_interfaces[0].primary_v4_address.address')
  TARGETS="$TARGETS --target subnet-name=${SUBNETS[$idx]},address=$IP"
done  # TODO some time later: maybe with jq mapping, just to get the feel of the command?

yc load-balancer target-group create --name "$PREFIX-tg" $TARGETS

echo "==> балансировщик"
TG_ID=$(yc load-balancer target-group get --name "$PREFIX-tg" --format json | jq -r .id)
yc load-balancer network-load-balancer create \
  --name "$PREFIX-lb" \
  --region-id ru-central1 \
  --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
  --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/
