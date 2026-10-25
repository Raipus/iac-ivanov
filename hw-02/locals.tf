locals {
  stand = "${var.prefix}-hw2"

  common_labels = {
    env   = var.env
    owner = var.prefix
  }
}
