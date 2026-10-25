# Стенд ДЗ 2: веб-серверы за балансировщиком в Terraform

## Что это за стенд

Демонстрационный стенд в Yandex Cloud, описанный манифестом Terraform. В нём своя сеть ivanov-01-hw2-net с двумя подсетями в разных зонах, веб-серверы с nginx (по умолчанию два, поровну по зонам), целевая группа и сетевой балансировщик. Балансировщик принимает запросы на порт 80, раздаёт их на порт 8003 веб-серверов и проверяет машины по HTTP. Каждый веб-сервер отдаёт страницу "labwork on <имя машины>".

## Что нужно

Terraform 1.8 или новее с зеркалом провайдеров Яндекса в ~/.terraformrc, Yandex CLI с настроенным профилем и ключ сервисного аккаунта с ролью editor на каталог.

### Переменные окружения

Блок provider пустой, доступ к облаку берётся из переменных окружения. Они живут до конца сеанса, поэтому их задают в каждом новом окне терминала:

```
export YC_SERVICE_ACCOUNT_KEY_FILE=$HOME/.yc-keys/ivanov-01-key.json
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID=$(yc config get folder-id)
export YC_ZONE=ru-central1-d
```

## Как поднять стенд
```
cd hw-02
terraform init
terraform plan
terraform apply
```
Через 1-2 минуты после apply машины поставят nginx. Адрес стенда выводит `terraform output -raw lb_url`. Проверить, что отвечают все машины:
```
LB=$(terraform output -raw lb_url)
for i in $(seq 1 40); do curl -s "$LB/"; done | sort | uniq -c
```
## Как снести стенд

`terraform destroy`

После этого в облаке не должно остаться ресурсов с именами ivanov-01-hw2. Проверка:
```
yc compute instance list
yc vpc network list
yc load-balancer network-load-balancer list.
```

## Если страница не открылась

1. Сразу после apply машины ещё ставят nginx: подождите 1-2 минуты и повторите запрос.
2. Посмотрите состояние целей балансировщика. UNHEALTHY у всех целей значит, что nginx не отвечает на порту 8003:
```
TG_ID=$(yc load-balancer target-group get --name ivanov-01-hw2-tg --format json | jq -r .id)
yc load-balancer network-load-balancer target-states --name ivanov-01-hw2-lb --target-group-id "$TG_ID"
```
3. Зайдите на машину по адресу из `terraform output web_ips` (`ssh student@<адрес>`) и проверьте настройку: `sudo cloud-init status --long`, затем `curl localhost:8003`.
4. Все цели HEALTHY, а отвечает одна машина: это нормально, балансировщик распределяет запросы по признакам соединения, а не по кругу. Поэтому выборка из 40 запросов.
5. `terraform apply` падает с отказом в правах или без ключа: в текущем окне терминала не заданы переменные `YC_*`.
6. `Quota ... exceeded`: в облаке остались ресурсы прошлых работ, удалите их через `yc`.