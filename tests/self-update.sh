#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cur="$(sed -n 's/^PC_VERSION=//p' "$repo/privy-cli" | head -1)"

# Фейковый docker: скрипт на старте проверяет compose и buildx
cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
case "$*" in
  'compose version') exit 0 ;;
  'buildx version') exit 1 ;;
  *) echo "unexpected docker command: $*" >&2; exit 91 ;;
esac
DOCKER

# Фейковый git: clone раскладывает «репозиторий» с файлом privy-cli,
# pull обновляет клон до FAKE_UPSTREAM_VERSION
cat > "$tmp/bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
dir=.
if [ "$1" = -C ]; then dir="$2"; shift 2; fi
case "$1" in
  clone)
    dest="${*: -1}"
    mkdir -p "$dest"
    printf 'PC_VERSION=%s\n' "$FAKE_UPSTREAM_VERSION" > "$dest/privy-cli"
    exit 0 ;;
  pull)
    printf 'PC_VERSION=%s\n' "$FAKE_UPSTREAM_VERSION" > "$dir/privy-cli"
    exit 0 ;;
  log)
    printf '    сейчас на: abcdef0 фейковый коммит (только что)\n'
    exit 0 ;;
esac
echo "unexpected git command: $*" >&2
exit 90
GIT
chmod +x "$tmp/bin/git" "$tmp/bin/docker"
export FAKE_UPSTREAM_VERSION

# 1) Установленная копия (рядом нет .git), upstream той же версии — замены нет
cp "$repo/privy-cli" "$tmp/bin/privy-cli"
FAKE_UPSTREAM_VERSION="$cur" PATH="$tmp/bin:$PATH" \
  "$tmp/bin/privy-cli" update self > "$tmp/same.log" 2>&1
grep -q 'уже последней версии' "$tmp/same.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/bin/privy-cli")" = "$cur"

# 2) Установленная копия: upstream новее — файл подменён, права на исполнение есть
FAKE_UPSTREAM_VERSION=9.9.9 PATH="$tmp/bin:$PATH" \
  "$tmp/bin/privy-cli" update self > "$tmp/upgrade.log" 2>&1
grep -q "обновлён: $cur → 9.9.9" "$tmp/upgrade.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/bin/privy-cli")" = 9.9.9
test -x "$tmp/bin/privy-cli"
test ! -e "$tmp/bin/.privy-cli.new."* 2>/dev/null || {
  echo 'остался временный файл подмены' >&2; exit 1;
}

# 3) Запуск из git-клона (рядом .git) — git pull клона вместо скачивания
mkdir -p "$tmp/clone/.git/objects"
cp "$repo/privy-cli" "$tmp/clone/privy-cli"
FAKE_UPSTREAM_VERSION=8.8.8 PATH="$tmp/bin:$PATH" \
  "$tmp/clone/privy-cli" update self > "$tmp/clone.log" 2>&1
grep -q "обновлён: $cur → 8.8.8" "$tmp/clone.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/clone/privy-cli")" = 8.8.8

echo 'self-update: installed copy replaced atomically, clone updated via git pull'
