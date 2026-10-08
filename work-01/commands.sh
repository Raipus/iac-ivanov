#!/usr/bin/env bash
# Журнал вводимых команд (практическая работа №1, вариат 01)

# Переменные
export PREFIX=ivanov-01
export ZONE=ru-central1-a
export CIDR=10.11.1.0/24
export DISK_SIZE=15

# Создание сети и подсети
yc vpc network create --name "$PREFIX-net"
yc vpc subnet create \
  --name "$PREFIX-subnet" \
  --network-name "$PREFIX-net" \
  --zone "$ZONE" \
  --range "$CIDR"

# Создание машины в сети 
yc compute instance create \
  --name "$PREFIX-web-1" \
  --zone "$ZONE" \
  --platform standard-v3 \
  --cores=2 \
  --core-fraction=20 \
  --memory=2 \
  --preemptible \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2404-lts,type=network-hdd,size="$DISK_SIZE" \
  --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
  --hostname "$PREFIX-web-1" \
  --ssh-key ~/.ssh/id_ed25519.pub \
  --labels created-by=cli

# Получение публичного адреса созданной ВМ
export VM_IP
VM_IP=$(yc compute instance get "$PREFIX-web-1" --format json \
  | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')

# Подключение и настройка ВМ
ssh yc-user@"$VM_IP"
sudo apt update
sudo apt install -y nginx
set +H
sudo sed -i "s|Welcome to nginx!|labwork on $(hostname)|g"   /var/www/html/index.nginx-debian.html
exit

# Сведения о ресурсах
yc compute instance list
yc compute instance list --format json
yc compute instance list --format json \
  | jq -r '.[] | "\(.name)\t\(.status)\t\(.network_interfaces[0].primary_v4_address.one_to_one_nat.address // "нет")"'
yc compute instance list --format json | jq -r ".[] | select(.name | startswith(\"$PREFIX\")) | .name"
yc compute instance list --format json | jq -r '.[] | select(.status != "RUNNING") | .name'

# Уборка
yc compute instance delete "$PREFIX-web-1"
yc compute instance delete "$PREFIX-web-manual"
yc vpc subnet delete "$PREFIX-subnet"
yc vpc network delete "$PREFIX-net"

# Проверка
yc compute instance list
yc vpc network list
yc compute disk list