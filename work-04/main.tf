# ---------- сеть ----------

resource "yandex_vpc_network" "net" {
  name = "ivanov-01-tf-net"
}

resource "yandex_vpc_subnet" "subnet" {
  name = "ivanov-01-tf-subnet"
  zone = "ru-central1-d"

  # ссылка на атрибут другого ресурса: отсюда Terraform узнаёт,
  # что сеть надо создать раньше подсети. Порядок нигде не задан явно
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.11.1.0/24"]
}

# ---------- образ ----------

# запрос к облаку во время планирования: какой сейчас свежий образ
# нужного семейства. Вместо строки-идентификатора, которая устареет
data "yandex_compute_image" "base" {
  family = "debian-12"
}

# ---------- диск ----------
resource "yandex_compute_disk" "disk" {
  name = "ivanov-01-tf-disk"
  zone = "ru-central1-d"
  size = 5
  type = "network-hdd"
}

# ---------- машина ----------

resource "yandex_compute_instance" "app" {
  allow_stopping_for_update = true
  name                      = "ivanov-01-tf-app"
  hostname                  = "ivanov-01-tf-app"
  zone                      = "ru-central1-d"
  platform_id               = "standard-v3"

  resources {
    cores         = 2
    core_fraction = 20
    memory        = 4
  }

  scheduling_policy {
    preemptible = true # прерываемая: дешевле, для учебного стенда достаточно
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.base.id
      size     = 15
      type     = "network-hdd"
    }
  }

  secondary_disk {
    disk_id = yandex_compute_disk.disk.id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true # публичный адрес
  }

  metadata = {
    # templatefile подставляет значения в шаблон — то же, что делал envsubst
    # во второй работе, только без внешней программы.
    # path.module — каталог, в котором лежит этот файл
    user-data = templatefile("${path.module}/cloud-init.tpl.yaml", {
      ssh_key = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
    })
  }

  labels = {
    env   = "lab"
    owner = "ivanov-01"
  }
}

# ---------- что вернуть после применения ----------

output "app_ip" {
  description = "публичный адрес машины"
  # у машины может быть несколько сетевых интерфейсов, поэтому к первому
  # обращаются по номеру: .0
  value = yandex_compute_instance.app.network_interface.0.nat_ip_address
}
