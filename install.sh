#!/usr/bin/env bash
# Устанавливает privy-client в /usr/local/bin, чтобы команда была доступна из любой папки.
# Запускать на сервере из корня репозитория: sudo ./install.sh
set -euo pipefail

cd "$(dirname "$0")"
sudo install -m 755 privy-client /usr/local/bin/privy-client
echo "готово: попробуйте 'privy-client help'"
