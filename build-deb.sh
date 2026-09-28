#!/usr/bin/env bash
# Собирает .deb-пакет: privy-client_<версия>_all.deb
# Ставится штатно: sudo apt install ./privy-client_<версия>_all.deb
# Нужен только dpkg-deb (есть в любой Ubuntu). Запускать из корня репозитория.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(sed -n 's/^PC_VERSION=\([^ #]*\).*/\1/p' privy-client | head -1)"
if [ -z "$VERSION" ]; then
  echo "не нашёл PC_VERSION в privy-client" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/DEBIAN"
install -D -m 755 privy-client "$STAGE/usr/bin/privy-client"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: privy-client
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Depends: git
Recommends: docker.io | docker-ce, nodejs | npm
Homepage: https://github.com/teper-ya-pomenyal/privy-client
Maintainer: Pomenyal <petr.lovlinka@gmail.com>
Description: одна команда для управления стеком Privy Stream на сервере
 install/update/uninstall/start/stop/restart/status/logs для бэкенда,
 веб-клиента и админки; приложения ставятся из GitHub в /opt/privy-stream.
EOF

dpkg-deb --root-owner-group --build "$STAGE" "privy-client_${VERSION}_all.deb"
echo
echo "готово: privy-client_${VERSION}_all.deb"
echo "установка: sudo apt install ./privy-client_${VERSION}_all.deb"
