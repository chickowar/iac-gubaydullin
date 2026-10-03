#   0) Войти в WSL с настроенным yc профилем и созданным сервисным аккаунтом
#   1) Настраиваем переменные окружения 
export PREFIX=gubaydullin-09
export ZONE=ru-central1-d
export CIDR=10.19.1.0/24
export DISK_SIZE=25

#   2) Создаём сеть и подсеть
yc vpc network create --name "$PREFIX-net"
yc vpc subnet create --name "$PREFIX-subnet" --network-name "$PREFIX-net" --zone "$ZONE" --range "$CIDR"
# yc vpc subnet list # check if subnet is created, not necessary

#   3) Создаём ВМ с заданными настройками
yc compute instance create --name "$PREFIX-web-1" \
 --hostname "$PREFIX-web-1" \
 --zone "$ZONE" \
 --platform standard-v3 \
 --cores=2 --core-fraction=20 --memory=2 \
 --preemptible \
 --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2404-lts,type=network-hdd,size="$DISK_SIZE" \
 --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
 --ssh-key ~/.ssh/id_ed25519.pub \
 --labels created-by=cli   # added hostname, otherwise hostname will be set as identifier from Yandex Cloud, which isn't cool
# yc compute instance list # check if created, not necessary


# # Nginx on server
# #   4) Подключаемся к ВМ по SSH
# export VM_IP=$(yc compute instance get "$PREFIX-web-1" --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')
# ssh -o StrictHostKeyChecking=accept-new yc-user@"$VM_IP" # '-o StrictHostKeyChecking=accept-new' to accept fingerprint, alternatively we just type 'yes' after
# #   5) Обновляем пакеты и устанавливаем nginx
# sudo apt update
# sudo apt install -y nginx
# #   6) Отключаем просмотр истории и меняем текст .html для веб-сервера
# set +H
# sudo sed -i "s|Welcome to nginx!|cloudlab on $(hostname)|g" \
#   /var/www/html/index.nginx-debian.html

# # Clean-up
# #   7) После можно удалить ВМ, сеть и подсеть
# yc compute instance delete "$PREFIX-web-1"
# yc compute instance delete "$PREFIX-web-manual"
# yc vpc subnet delete "$PREFIX-subnet"
# yc vpc network delete "$PREFIX-net"