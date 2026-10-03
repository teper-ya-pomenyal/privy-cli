#!/usr/bin/env bash
# Собирает .deb-пакет: privy-cli_<версия>_all.deb
# Ставится штатно: sudo apt install ./privy-cli_<версия>_all.deb
# Нужен только dpkg-deb (есть в любой Ubuntu). Запускать из корня репозитория.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(sed -n 's/^PC_VERSION=\([^ #]*\).*/\1/p' privy-cli | head -1)"
if [ -z "$VERSION" ]; then
  echo "не нашёл PC_VERSION в privy-cli" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/DEBIAN"
install -D -m 755 privy-cli "$STAGE/usr/bin/privy-cli"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: privy-cli
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Depends: git
Conflicts: privy-client
Replaces: privy-client
Provides: privy-client
Recommends: docker.io | docker-ce, nodejs | npm
Homepage: https://github.com/teper-ya-pomenyal/privy-cli
Maintainer: Pomenyal <petr.lovlinka@gmail.com>
Description: одна команда для управления стеком Privy Stream на сервере
 install/update/rollback/uninstall/start/stop/restart/status/logs для бэкенда,
 веб-клиента и админки; приложения ставятся из GitHub в /opt/privy-stream.
EOF

dpkg-deb --root-owner-group --build "$STAGE" "privy-cli_${VERSION}_all.deb"
echo
echo "готово: privy-cli_${VERSION}_all.deb"
echo "установка: sudo apt install ./privy-cli_${VERSION}_all.deb"
