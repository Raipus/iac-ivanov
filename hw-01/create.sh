#!/usr/bin/env bash
set -euo pipefail

# ---- параметры варианта ----
PREFIX="${1:-ivanov-01}"              # префикс имён ресурсов
ZONE_A="${2:-ru-central1-a}"          # зона A
ZONE_B="${3:-ru-central1-b}"          # зона B
CIDR_A="${4:-10.11.1.0/24}"           # подсеть в зоне A
CIDR_B="${5:-10.11.2.0/24}"           # подсеть в зоне B
APP_PORT="${6:-8003}"                 # порт, на котором отвечает nginx
GREETING="${7:-labwork}"              # слово из варианта, оно же на странице
VM_COUNT="${8:-2}"                    # число машин в группе
BOOT_SIZE="${9:-15}"                  # загрузочный диск, ГБ — из варианта
IMAGE_FAMILY="${10:-ubuntu-2404-lts}" # образ машин, одинаковый у всех вариантов
ENV_NAME="${11:-lab}"                 # имя окружения


echo "==> сеть"
if yc vpc network get --name "$PREFIX-net" > /dev/null 2>&1; then
  echo "сеть '$PREFIX-net' уже создана"
else
  yc vpc network create --name "$PREFIX-net" --labels "env=$ENV_NAME,owner=$PREFIX"
fi

echo "==> подсети"
if yc vpc subnet get --name "$PREFIX-subnet-a" > /dev/null 2>&1; then
  echo "подсеть '$PREFIX-subnet-a' уже создана"
else
  yc vpc subnet create --name "$PREFIX-subnet-a" --network-name "$PREFIX-net" \
    --zone "$ZONE_A" --range "$CIDR_A" --labels "env=$ENV_NAME,owner=$PREFIX"
fi

if yc vpc subnet get --name "$PREFIX-subnet-b" > /dev/null 2>&1; then
  echo "подсеть '$PREFIX-subnet-b' уже создана"
else
  yc vpc subnet create --name "$PREFIX-subnet-b" --network-name "$PREFIX-net" \
    --zone "$ZONE_B" --range "$CIDR_B" --labels "env=$ENV_NAME,owner=$PREFIX"
fi

echo "==> NAT шлюз"
if yc vpc gateway get --name "$PREFIX-nat" > /dev/null 2>&1; then
  echo "NAT шлюз '$PREFIX-nat' уже создан"
else
  yc vpc gateway create --name "$PREFIX-nat" --labels "env=$ENV_NAME,owner=$PREFIX"
fi

echo "==> таблица маршрутизации"
GW_ID=$(yc vpc gateway get --name "$PREFIX-nat" --format json | jq -r .id)

if yc vpc route-table get --name "$PREFIX-rt" > /dev/null 2>&1; then
  echo "таблица маршрутизации '$PREFIX-rt' уже создана"
else
  yc vpc route-table create --name "$PREFIX-rt" --network-name "$PREFIX-net" \
  --route "destination=0.0.0.0/0,gateway-id=$GW_ID" \
  --labels "env=$ENV_NAME,owner=$PREFIX"
fi

echo "==> привязка таблицы к подсети"
if yc vpc route-table get --name "$PREFIX-rt" >/dev/null 2>&1; then
  RT_ID=$(yc vpc route-table get --name "$PREFIX-rt" --format json | jq -r '.id')
  CURRENT_RT_ID=$(yc vpc subnet get --name "$PREFIX-subnet-a" --format json | jq -r '.route_table_id // empty')
  if [ "$CURRENT_RT_ID" = "$RT_ID" ]; then
    echo "таблица '$PREFIX-rt' уже привязана к подсети '$PREFIX-subnet-a'"
  else
    yc vpc subnet update --name "$PREFIX-subnet-a" --route-table-name "$PREFIX-rt"
  fi
else
  echo "таблица '$PREFIX-rt' не найдена"
fi

echo "==> файл настройки из шаблона"
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export APP_PORT GREETING SSH_KEY
envsubst '${APP_PORT} ${GREETING} ${SSH_KEY}' \
  < hw-01/cloud-init.tpl.yaml > hw-01/cloud-init.yaml

echo "==> веб сервера"
ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$PREFIX-subnet-a" "$PREFIX-subnet-b")

for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  if yc compute instance get --name "$PREFIX-web-$i" > /dev/null 2>&1; then
    echo "веб сервер '$PREFIX-web-$i' уже создан"
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
      --metadata-from-file user-data=hw-01/cloud-init.yaml \
      --labels "env=$ENV_NAME,owner=$PREFIX"
  fi
done

echo "==> сервер приложения"
if yc compute instance get --name "$PREFIX-app-1" > /dev/null 2>&1; then
  echo "сервер приложения '$PREFIX-app-1' уже создан"
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
    --metadata-from-file user-data=hw-01/cloud-init.yaml \
    --labels "env=$ENV_NAME,owner=$PREFIX"
fi

echo "==> целевая группа"
TARGETS=""
for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  IP=$(yc compute instance get "$PREFIX-web-$i" --format json \
    | jq -r '.network_interfaces[0].primary_v4_address.address')
  TARGETS="$TARGETS --target subnet-name=${SUBNETS[$idx]},address=$IP"
done

if yc load-balancer target-group get --name "$PREFIX-tg"> /dev/null 2>&1; then
  echo "целевая группа '$PREFIX-tg' уже создана"
else
  yc load-balancer target-group create --name "$PREFIX-tg" $TARGETS --labels "env=$ENV_NAME,owner=$PREFIX"
fi

echo "==> балансировщик"
TG_ID=$(yc load-balancer target-group get --name "$PREFIX-tg" --format json | jq -r .id)
if yc load-balancer network-load-balancer get --name "$PREFIX-lb"> /dev/null 2>&1; then
  echo "балансировщик '$PREFIX-lb' уже создан"
else
  yc load-balancer network-load-balancer create \
    --name "$PREFIX-lb" \
    --region-id ru-central1 \
    --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
    --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/ \
    --labels "env=$ENV_NAME,owner=$PREFIX"
fi

LB_IP=$(yc load-balancer network-load-balancer get --name "$PREFIX-lb" --format json | jq -r '.listeners[0].address')
echo "Стенд готов, балансировщик доступен по адресу: http://$LB_IP"