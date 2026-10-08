#!/usr/bin/env bash

# ---- параметры варианта ----
PREFIX="${1:-ivanov-01}"              # префикс — он же значение labels.owner
# shellcheck disable=SC2034  # используется в удалённой команде по ssh
APP_PORT="${2:-8003}"                 # порт, на котором отвечает nginx

# ---- служебное ----
FAIL=0                                # 0 — все проверки прошли, 1 — хотя бы одна упала
SSH_USER=student                      # пользователь на обеих ВМ

echo "==> проверка 1: балансировщик отвечает 200"
LB_IP=$(yc load-balancer network-load-balancer list --format json \
        | jq -r ".[] | select(.labels.owner == \"$PREFIX\")
                     | .listeners[0].address // empty" \
        | head -n1)
if [ -z "$LB_IP" ]; then
  echo "X балансировщик недоступен"
  FAIL=1
else
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$LB_IP/")
  if [ "$CODE" = "200" ]; then
    echo "V балансировщик отвечает: 200"
  else
    echo "X балансировщик отвечает: $CODE"
    FAIL=1
  fi
fi

echo "==> проверка 2: ответы приходят больше чем с одной машины"
if [ -z "$LB_IP" ]; then
  echo "X балансировщик недоступен"
  FAIL=1
else
  NAMES=$(for _ in $(seq 1 10); do
            curl -s --max-time 10 "http://$LB_IP/" \
              | grep -oE "${PREFIX}-web-[0-9]+" | head -n1
          done | sort -u | paste -sd, -)

  UNIQ=$(printf '%s\n' "$NAMES" | tr ',' '\n' | grep -c . || true)
  if [ "$UNIQ" -gt 1 ]; then
    echo "V ответили машины: $NAMES"
  else
    echo "X ответила только одна машина: ${NAMES:-нет ответа}"
    FAIL=1
  fi
fi

echo "==> проверка 3: сервер приложения доступен с веб-сервера по внутреннему адресу"
WEB_PUB=$(yc compute instance list --format json \
          | jq -r ".[] | select(.labels.owner == \"$PREFIX\")
                       | select(.name | startswith(\"${PREFIX}-web-1\"))
                       | .network_interfaces[0].primary_v4_address.one_to_one_nat.address // empty" \
          | head -n1)

APP_INT=$(yc compute instance list --format json \
          | jq -r ".[] | select(.labels.owner == \"$PREFIX\")
                       | select(.name | startswith(\"${PREFIX}-app-1\"))
                       | .network_interfaces[0].primary_v4_address.address // empty" \
          | head -n1)

if [ -z "$WEB_PUB" ] || [ -z "$APP_INT" ]; then
  echo "X не удалось получить адреса (web=$WEB_PUB, app=$APP_INT)"
  FAIL=1
else
  RC=$(ssh "$SSH_USER@$WEB_PUB" \
         "curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://\$APP_INT:\$APP_PORT/" \
       2>/dev/null || echo 000)
  if [ "$RC" = "200" ]; then
    echo "V сервер приложения доступен с $WEB_PUB"
  else
    echo "X сервер приложения недоступен с $WEB_PUB"
    FAIL=1
  fi
fi

echo "Код возврата: '$FAIL'"
exit $FAIL