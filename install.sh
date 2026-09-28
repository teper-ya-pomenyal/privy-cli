#!/usr/bin/env bash
# Устанавливает privy-cli в /usr/local/bin, чтобы команда была доступна из любой папки.
# Запускать на сервере из корня репозитория: sudo ./install.sh
set -euo pipefail

cd "$(dirname "$0")"
sudo install -m 755 privy-cli /usr/local/bin/privy-cli
echo "готово: попробуйте 'privy-cli help'"
