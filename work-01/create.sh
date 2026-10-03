#!/usr/bin/env bash
set -euo pipefail

# 1) Задаём переменные окружения
export PREFIX=gubaydullin-09; export ZONE=ru-central1-d; export CIDR=10.19.1.0/24; export DISK_SIZE=25; export IMAGE_FAMILY=debian-12
echo "Env variables: PREFIX=$PREFIX | ZONE=$ZONE | CIDR=$CIDR | DISK_SIZE: $DISK_SIZE | IMAGE_FAMILY=$IMAGE_FAMILY"

# 2) Создаём сеть и подсеть
echo "Creating network $PREFIX-net"
yc vpc network create --name "$PREFIX-net"
echo "Creating subnetwork $PREFIX-subnet"
yc vpc subnet create --name "$PREFIX-subnet" --network-name "$PREFIX-net" --zone "$ZONE" --range "$CIDR"

# 3) Поднимаем 2 ВМ
for INDEX in 1 2; do
    echo "Creating $PREFIX-app-$INDEX"
    yc compute instance create --name "$PREFIX-app-$INDEX" \
    --hostname "$PREFIX-app-$INDEX" \
    --zone "$ZONE" \
    --platform standard-v3 \
    --cores=2 --core-fraction=20 --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$DISK_SIZE" \
    --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
    --ssh-key ~/.ssh/id_ed25519.pub \
    --labels created-by=cli
done

# Nginx on both servers (manually)
# 4) В локальном WSL получаем адреса обеих ВМ.
# После bash create.sh переменные скрипта не сохраняются в родительской оболочке.
# export PREFIX=gubaydullin-09
# VM_IP_1=$(yc compute instance get "$PREFIX-app-1" --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')
# VM_IP_2=$(yc compute instance get "$PREFIX-app-2" --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')
# ssh -o StrictHostKeyChecking=accept-new yc-user@"$VM_IP_1"
#
# 5) На ВМ-1 устанавливаем nginx и настраиваем порт 8027 для IPv4 и IPv6.
# PORT=8027
# PAGE_WORD=cloudlab
# sudo apt update
# sudo apt install -y nginx
# sudo sed -i -E \
#   "s/(listen[[:space:]]+(\[::\]:)?)80([[:space:];])/\1$PORT\3/g" \
#   /etc/nginx/sites-available/default
# sudo nginx -t
# sudo systemctl reload nginx
#
# 6) Отключаем подстановку истории Bash и персонализируем страницу.
# set +H
# sudo sed -i "s|Welcome to nginx!|$PAGE_WORD on $(hostname)|g" \
#   /var/www/html/index.nginx-debian.html
# curl -fsS "http://localhost:$PORT/" | grep "$PAGE_WORD"
# exit
#
# 7) Из локального WSL подключаемся к ВМ-2 и повторяем шаги 5–6.
# ssh -o StrictHostKeyChecking=accept-new yc-user@"$VM_IP_2"