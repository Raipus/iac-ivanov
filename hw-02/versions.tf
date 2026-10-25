terraform {
  required_version = ">= 1.8"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.220.0"
    }
  }
}

# блок пуст намеренно: ключ сервисного аккаунта, облако, каталог и зона
# приходят из переменных окружения YC_SERVICE_ACCOUNT_KEY_FILE, YC_CLOUD_ID,
# YC_FOLDER_ID и YC_ZONE. Так validate проходит в пайплайне, где файла
# ключа нет, а путь к ключу и идентификаторы не попадают в репозиторий
provider "yandex" {}