# 1) Задаём переменные окружения
export PREFIX=gubaydullin-09; export ZONE=ru-central1-d; export CIDR=10.19.1.0/24; export DISK_SIZE=25
echo "Env variables: PREFIX=$PREFIX | ZONE=$ZONE | CIDR=$CIDR | DISK_SIZE: $DISK_SIZE"

# 2) Создаём сеть и подсеть
echo "Crearing network $PREFIX-net"
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
    --create-boot-disk image-folder-id=standard-images,image-family=debian-12,type=network-hdd,size="$DISK_SIZE" \
    --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
    --ssh-key ~/.ssh/id_ed25519.pub \
    --labels created-by=cli
done

# # Nginx on servers (manually)
# #   4) Подключаемся к ВМ-1 по SSH
# export VM_IP_1=$(yc compute instance get "$PREFIX-app-1" --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')
# ssh -o StrictHostKeyChecking=accept-new yc-user@"$VM_IP_1"
# #   5) Обновляем пакеты и устанавливаем nginx
# sudo apt update
# sudo apt install -y nginx
# #   6) Отключаем просмотр истории и меняем текст .html для веб-сервера
# set +H
# sudo sed -i "s|Welcome to nginx!|cloudlab on $(hostname)|g" \
#   /var/www/html/index.nginx-debian.html