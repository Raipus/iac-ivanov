variable "prefix" {
  description = "Префикс имён ресурсов: фамилия и номер варианта"
  type        = string
}

variable "zone_a" {
  description = "Зона А"
  type        = string
}

variable "zone_b" {
  description = "Зона Б"
  type        = string
}

variable "cidr_a" {
  description = "Подсеть А"
  type        = string
}

variable "cidr_b" {
  description = "Подсеть Б"
  type        = string
}

variable "app_port" {
  description = "Порт сервиса"
  type        = number
  validation {
    condition     = var.app_port > 1023 && var.app_port < 65536
    error_message = "Порт должен быть в диапазоне 1024–65535."
  }
}

variable "disk_size" {
  description = "Размер загрузочного диска, ГБ"
  type        = number
  default     = 15
}


variable "greeting" {
  description = "Слово на странице"
  type        = string
}

variable "vm_count" {
  description = "Число веб-серверов"
  type        = number
  default     = 2
}

variable "image_family" {
  description = "Дистрибутив"
  type        = string
}

variable "env" {
  description = "Имя окружения, ставится меткой"
  type        = string
}