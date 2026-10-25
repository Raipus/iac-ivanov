output "lb_url" {
  # слушатель и его внешний адрес описаны множествами, по индексу их не взять:
  # адреса собираются циклом, one берёт единственный
  value = "http://${one(flatten([
    for l in yandex_lb_network_load_balancer.lb.listener : [
      for spec in l.external_address_spec : spec.address
    ]
  ]))}"
}

output "web_ips" {
  description = "Публичные адреса веб-серверов"
  value       = yandex_compute_instance.web[*].network_interface.0.nat_ip_address
}