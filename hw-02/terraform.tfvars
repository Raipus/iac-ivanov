prefix       = "ivanov-01"
# зоны варианта ru-central1-a и ru-central1-b заменены на ru-central1-d
# и ru-central1-e из-за ограничений ресурсов облака
zone_a       = "ru-central1-d"
zone_b       = "ru-central1-e"
cidr_a       = "10.11.1.0/24"
cidr_b       = "10.11.2.0/24"
app_port     = 8003
disk_size    = 15
vm_count     = 2
image_family = "debian-12"
greeting     = "labwork"
env          = "lab"