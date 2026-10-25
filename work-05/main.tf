# ---------- сеть ----------

resource "yandex_vpc_network" "net" {
  name   = "${local.stand}-net"
  labels = local.common_labels
}

resource "yandex_vpc_subnet" "subnet" {
  name = "${local.stand}-subnet"
  zone = var.zone

  # ссылка на атрибут другого ресурса: отсюда Terraform узнаёт,
  # что сеть надо создать раньше подсети. Порядок нигде не задан явно
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = [var.subnet_cidr]

  labels = local.common_labels
}

# ---------- образ ----------

# запрос к облаку во время планирования: какой сейчас свежий образ
# нужного семейства. Вместо строки-идентификатора, которая устареет
data "yandex_compute_image" "base" {
  family = var.image_family
}

# ---------- машина ----------

resource "yandex_compute_instance" "app" {
  # ключи "1", "2", … по числу машин из варианта
  for_each                  = toset([for i in range(var.vm_count) : tostring(i + 1)])
  allow_stopping_for_update = true
  name                      = "${local.stand}-app-${each.key}"
  hostname                  = "${local.stand}-app-${each.key}"
  # остальное без изменений
  zone        = var.zone
  platform_id = "standard-v3"

  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }

  scheduling_policy {
    preemptible = true # прерываемая: дешевле, для учебного стенда достаточно
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.base.id
      size     = var.disk_size
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet.id
    nat                = true # публичный адрес
    security_group_ids = [yandex_vpc_security_group.app.id]
  }

  metadata = {
    # templatefile подставляет значения в шаблон — то же, что делал envsubst
    # во второй работе, только без внешней программы.
    # path.module — каталог, в котором лежит этот файл
    user-data = templatefile("${path.module}/cloud-init.tpl.yaml", {
      ssh_key      = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
      app_port     = var.app_port
      greeting     = var.greeting
      web_password = var.web_password
    })
  }

  labels = local.common_labels
}

# машина не переезжала: изменился только её адрес в коде
moved {
  from = yandex_compute_instance.app
  to   = yandex_compute_instance.app["1"]
}
