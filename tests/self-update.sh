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
# pull обновляет клон до FAKE_UPSTREAM_VERSION и сдвигает fake-HEAD,
# checkout возвращает файл к FAKE_PREV_VERSION (так делает rollback cli).
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
    printf '%s' "${FAKE_HEAD_SHA:-2222222}" > "$dir/.git/fake-head"
    exit 0 ;;
  log)
    printf 'abcdef0 фейковый коммит (только что)\n'
    exit 0 ;;
  rev-parse)
    if [ "$2" = HEAD ]; then
      cat "$dir/.git/fake-head" 2>/dev/null || printf '1111111'
      exit 0
    fi
    if [ "$2" = --absolute-git-dir ]; then
      printf '%s/.git\n' "$dir"
      exit 0
    fi ;;
  symbolic-ref)
    printf 'main'
    exit 0 ;;
  checkout)
    # вызов всегда «checkout -q <sha> --»
    printf 'PC_VERSION=%s\n' "$FAKE_PREV_VERSION" > "$dir/privy-cli"
    printf '%s' "${3:-$2}" > "$dir/.git/fake-head"
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

# 2) Установленная копия: upstream новее — файл подменён, прежняя версия
#    сохранена рядом для rollback, права на исполнение есть
FAKE_UPSTREAM_VERSION=9.9.9 PATH="$tmp/bin:$PATH" \
  "$tmp/bin/privy-cli" update self > "$tmp/upgrade.log" 2>&1
grep -q "обновлён: $cur → 9.9.9" "$tmp/upgrade.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/bin/privy-cli")" = 9.9.9
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/bin/.privy-cli.prev")" = "$cur"
test -x "$tmp/bin/privy-cli" && test -x "$tmp/bin/.privy-cli.prev"
test ! -e "$tmp/bin/.privy-cli.new."* 2>/dev/null || {
  echo 'остался временный файл подмены' >&2; exit 1;
}

# 3) Откат установленной копии — обмен с .privy-cli.prev.
#    Fake-upstream оставил однострочный файл; в реальности там полный скрипт —
#    кладём настоящий той же версии, чтобы rollback исполнял реальный код.
sed "s/^PC_VERSION=.*/PC_VERSION=9.9.9/" "$repo/privy-cli" > "$tmp/bin/privy-cli"
chmod 755 "$tmp/bin/privy-cli"
PATH="$tmp/bin:$PATH" "$tmp/bin/privy-cli" rollback self > "$tmp/cli-rollback.log" 2>&1
grep -q "откат 9.9.9 → $cur" "$tmp/cli-rollback.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/bin/privy-cli")" = "$cur"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/bin/.privy-cli.prev")" = 9.9.9
test -x "$tmp/bin/privy-cli"

# 4) Повторный откат возвращает обновлённую версию (обмен обратим)
PATH="$tmp/bin:$PATH" "$tmp/bin/privy-cli" rollback self > "$tmp/cli-rollback2.log" 2>&1
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/bin/privy-cli")" = 9.9.9
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/bin/.privy-cli.prev")" = "$cur"

# 5) Запуск из git-клона (рядом .git) — git pull клона вместо скачивания,
#    точка отката записывается в .git
mkdir -p "$tmp/clone/.git/objects"
cp "$repo/privy-cli" "$tmp/clone/privy-cli"
FAKE_UPSTREAM_VERSION=8.8.8 FAKE_HEAD_SHA=feed222 PATH="$tmp/bin:$PATH" \
  "$tmp/clone/privy-cli" update self > "$tmp/clone.log" 2>&1
grep -q "обновлён: $cur → 8.8.8" "$tmp/clone.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/clone/privy-cli")" = 8.8.8
test "$(sed -n 's/^commit=//p' "$tmp/clone/.git/privy-cli-rollback")" = 1111111
grep -q '^branch=main$' "$tmp/clone/.git/privy-cli-rollback"

# 6) rollback self в git-клоне — checkout записанной точки отката.
#    После fake-pull в клоне однострочный файл; кладём настоящий скрипт
#    той же версии, чтобы rollback исполнял реальный код.
sed "s/^PC_VERSION=.*/PC_VERSION=8.8.8/" "$repo/privy-cli" > "$tmp/clone/privy-cli"
chmod 755 "$tmp/clone/privy-cli"
FAKE_PREV_VERSION="$cur" PATH="$tmp/bin:$PATH" \
  "$tmp/clone/privy-cli" rollback self > "$tmp/clone-rollback.log" 2>&1
grep -q "откачен: 8.8.8 → $cur" "$tmp/clone-rollback.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/clone/privy-cli")" = "$cur"
test "$(cat "$tmp/clone/.git/fake-head")" = 1111111

# 7) Повторный rollback — уже откачено, без изменений
#    (fake-checkout снова записал в клон однострочник — сеем настоящий скрипт)
sed "s/^PC_VERSION=.*/PC_VERSION=$cur/" "$repo/privy-cli" > "$tmp/clone/privy-cli"
chmod 755 "$tmp/clone/privy-cli"
FAKE_PREV_VERSION="$cur" PATH="$tmp/bin:$PATH" \
  "$tmp/clone/privy-cli" rollback self > "$tmp/clone-rollback2.log" 2>&1
grep -q 'откат уже выполнен' "$tmp/clone-rollback2.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/clone/privy-cli")" = "$cur"

echo 'self-update: installed copy replaced atomically (с .privy-cli.prev для rollback), clone updated via git pull'
