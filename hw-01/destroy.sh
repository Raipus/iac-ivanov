#!/usr/bin/env bash
set -euo pipefail

# ---- параметры варианта ----
PREFIX="${1:-ivanov-01}"

echo "==> балансировщики"
for i in $(yc load-balancer network-load-balancer list --format json | jq -r ".[] | select(.labels.owner == \"$PREFIX\") | .name"); do
  yc load-balancer network-load-balancer delete "$i"
done

echo "==> целевые группы"
for i in $(yc load-balancer target-group list --format json | jq -r ".[] | select(.labels.owner == \"$PREFIX\") | .name"); do
  yc load-balancer target-group delete "$i"
done

echo "==> виртуальные машины"
for i in $(yc compute instance list --format json | jq -r ".[] | select(.labels.owner == \"$PREFIX\") | .name"); do
  yc compute instance delete "$i"
done

echo "==> отвязка таблиц от подсетей"
for n in $(yc vpc subnet list --format json | jq -r ".[] | select(.labels.owner == \"$PREFIX\") | .name"); do
  RT=$(yc vpc subnet get \
    --name "$n" \
    --format json \
    | jq -r '.route_table_id // empty')

  if [[ -n "$RT" ]]; then
    yc vpc subnet update \
      --name "$n" \
      --disassociate-route-table
  fi
done

echo "==> таблицы маршрутизации"
for n in $(yc vpc route-table list --format json | jq -r ".[] | select(.labels.owner == \"$PREFIX\") | .name"); do
  yc vpc route-table delete --name "$n"
done

echo "==> NAT-шлюзы"
for n in $(yc vpc gateway list --format json | jq -r ".[] | select(.labels.owner == \"$PREFIX\") | .name"); do
  yc vpc gateway delete --name "$n"
done

echo "==> подсети"
for i in $(yc vpc subnet list --format json | jq -r ".[] | select(.labels.owner == \"$PREFIX\") | .name"); do
  yc vpc subnet delete "$i"
done

echo "==> сети"
for i in $(yc vpc network list --format json | jq -r ".[] | select(.labels.owner == \"$PREFIX\") | .name"); do
  yc vpc network delete "$i"
done

echo "==> вывод оставшихся данных"
yc compute instance list
yc vpc network list
yc compute disk list
yc vpc address list
yc load-balancer network-load-balancer list

echo "Уборка окончена"