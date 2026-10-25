resource "yandex_vpc_network" "net" {
  name   = "${local.stand}-net"
  labels = local.common_labels
}

resource "yandex_vpc_subnet" "subnet_a" {
  name           = "${local.stand}-subnet-a"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = [var.cidr_a]
  zone           = var.zone_a
  labels         = local.common_labels
}

resource "yandex_vpc_subnet" "subnet_b" {
  name           = "${local.stand}-subnet-b"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = [var.cidr_b]
  zone           = var.zone_b
  labels         = local.common_labels
}

data "yandex_compute_image" "os" {
  family = var.image_family
}

resource "yandex_compute_instance" "web" {
  # число машин задаётся в terraform.tfvars (vm_count). Номер count.index
  # входит в адрес ресурса в состоянии: при уменьшении числа удаляются
  # машины с конца списка, а не выбранные
  count = var.vm_count

  name     = "${local.stand}-web-${count.index + 1}"
  hostname = "${local.stand}-web-${count.index + 1}"

  # чётные номера в зону A, нечётные в зону B: машины делятся между зонами,
  # и отказ одной зоны не гасит весь стенд
  zone = count.index % 2 == 0 ? var.zone_a : var.zone_b

  network_interface {
    # подсеть выбирается по той же чётности: она должна быть в зоне машины
    subnet_id = count.index % 2 == 0 ? yandex_vpc_subnet.subnet_a.id : yandex_vpc_subnet.subnet_b.id
    nat       = true
  }


  platform_id = "standard-v3"
  resources {
    memory        = 2
    cores         = 2
    core_fraction = 20
  }

  scheduling_policy {
    preemptible = true
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.os.id
      size     = var.disk_size
      type     = "network-hdd"
    }
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.tpl.yaml", {
      ssh_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINzXrYc+LQtXGAPnfSvrPkKzVcmnhFqjVwaTaRyiDeOw ivanov-01"
      app_port = var.app_port
      greeting = var.greeting
    })
  }

  allow_stopping_for_update = true

  labels = local.common_labels
}

resource "yandex_lb_target_group" "tg" {
  name = "${local.stand}-tg"

  dynamic "target" {
    for_each = yandex_compute_instance.web
    # адрес внутренний: балансировщик ходит к машинам по сети облака.
    # С публичным nat_ip_address группа создастся, но цели не станут HEALTHY
    content {
      subnet_id = target.value.network_interface.0.subnet_id
      address   = target.value.network_interface.0.ip_address
    }
  }

  labels = local.common_labels
}

resource "yandex_lb_network_load_balancer" "lb" {
  name = "${local.stand}-lb"

  region_id = "ru-central1"

  # снаружи принимает на 80, на машины передаёт на порт сервиса
  listener {
    name        = "http"
    port        = 80
    target_port = var.app_port
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.tg.id

    # проверка идёт на порт сервиса: на 80 nginx не слушает,
    # и с проверкой на 80 все цели были бы UNHEALTHY
    healthcheck {
      name                = "http"
      interval            = 2
      timeout             = 1
      unhealthy_threshold = 2
      healthy_threshold   = 2
      http_options {
        port = var.app_port
        path = "/"
      }
    }
  }

  labels = local.common_labels
}