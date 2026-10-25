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
  count = 2

  name     = "${local.stand}-web-${count.index + 1}"
  hostname = "${local.stand}-web-${count.index + 1}"

  zone = count.index % 2 == 0 ? var.zone_a : var.zone_b

  network_interface {
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

    healthcheck {
      name                = "http"
      interval            = 2
      timeout             = 1
      unhealthy_threshold = 2
      healthy_threshold   = 2
      http_options {
        port = var.app_port
      }
    }
  }

  labels = local.common_labels
}