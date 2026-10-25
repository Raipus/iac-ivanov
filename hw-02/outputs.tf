output "lb_url" {
  value = "http://${one(flatten([
    for l in yandex_lb_network_load_balancer.lb.listener : [
      for spec in l.external_address_spec : spec.address
    ]
  ]))}"
}
