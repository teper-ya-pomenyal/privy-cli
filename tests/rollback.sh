#!/usr/bin/env bash
# Откат приложений и самого cli: настоящий git + фейковые docker/npm.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/apps"

UPS_LOG="$tmp/ups.log" NPM_LOG="$tmp/npm.log"
export UPS_LOG NPM_LOG
: > "$UPS_LOG"
: > "$NPM_LOG"

# Фейковый docker: compose есть, buildx нет; «сборка» логируется, контейнера
# админки не существует, чистка мусора проходит молча. Важно отвечать на все
# проверки: иначе CLI возьмёт настоящий docker/docker-compose с машины.
cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
case "$*" in
  'compose version') exit 0 ;;
esac
case "$1" in
  buildx) exit 1 ;;
  compose)
    case "${*: -3}" in
      'up -d --build') echo up >> "$UPS_LOG"; exit 0 ;;
    esac
    case "$2" in
      ps) exit 0 ;;
    esac
    echo "unexpected docker compose: $*" >&2; exit 91 ;;
  ps) exit 0 ;;
  image | builder) exit 0 ;;
esac
echo "unexpected docker command: $*" >&2
exit 91
DOCKER

# Фейковый npm: каждый вызов логируется, build создаёт dist/index.html
cat > "$tmp/bin/npm" <<'NPM'
#!/usr/bin/env bash
echo "npm $*" >> "$NPM_LOG"
case "$1 $2" in
  'run build') mkdir -p dist && : > dist/index.html ;;
esac
exit 0
NPM

chmod +x "$tmp/bin/docker" "$tmp/bin/npm"

git_commit() { local dir="$1"; shift; git -C "$dir" -c user.name=test -c user.email=test@test commit -q "$@"; }
head_of()    { git -C "$1" rev-parse HEAD; }
state_of()   { sed -n 's/^commit=//p' "$1/.git/privy-cli-rollback"; }
branch_of()  { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || true; }
lines()      { wc -l < "$1" | tr -d '[:space:]'; } # wc -l на macOS отбивает число пробелами

run() { PATH="$tmp/bin:$PATH" "$repo/privy-cli" "$@"; }

run_fail() { # run_fail <файл-вывода> <аргументы privy-cli…> — ожидаем ошибку
  local log="$1"; shift
  if PATH="$tmp/bin:$PATH" "$repo/privy-cli" "$@" > "$log" 2>&1; then
    echo "ожидалась ошибка: privy-cli $*" >&2
    exit 1
  fi
}

# --- backend: compose-приложение, upstream ушёл на v2 ----------------------

git init -q -b main "$tmp/rem-backend"
printf 'services:\n  app:\n    image: busybox\n' > "$tmp/rem-backend/docker-compose.yml"
git -C "$tmp/rem-backend" add -A
git_commit "$tmp/rem-backend" -m 'v1'
git clone -q "$tmp/rem-backend" "$tmp/apps/privy-server"
printf '# v2\n' >> "$tmp/rem-backend/docker-compose.yml"
git_commit "$tmp/rem-backend" -a -m 'v2'
C1="$(git -C "$tmp/rem-backend" rev-parse HEAD~1)"
C2="$(git -C "$tmp/rem-backend" rev-parse HEAD)"
export BACKEND_DIR="$tmp/apps/privy-server"

# 1) update сдвигает HEAD и записывает точку отката
run update backend > "$tmp/update.log" 2>&1
test "$(head_of "$BACKEND_DIR")" = "$C2"
test "$(state_of "$BACKEND_DIR")" = "$C1"
grep -q '^branch=main$' "$BACKEND_DIR/.git/privy-cli-rollback"
test "$(lines "$UPS_LOG")" -eq 1

# 2) rollback возвращает прошлый коммит (HEAD отсоединён) и пересобирает
run rollback backend > "$tmp/rollback.log" 2>&1
grep -q 'откат на' "$tmp/rollback.log"
test "$(head_of "$BACKEND_DIR")" = "$C1"
test -z "$(branch_of "$BACKEND_DIR")"
test "$(lines "$UPS_LOG")" -eq 2

# 3) повторный rollback — уже выполнен, без лишней пересборки
run rollback backend > "$tmp/rollback2.log" 2>&1
grep -q 'откат уже выполнен' "$tmp/rollback2.log"
test "$(lines "$UPS_LOG")" -eq 2

# 4) update после отката: возврат на ветку, точка отката сохраняется
run update backend > "$tmp/update2.log" 2>&1
test "$(head_of "$BACKEND_DIR")" = "$C2"
test "$(branch_of "$BACKEND_DIR")" = "main"
test "$(state_of "$BACKEND_DIR")" = "$C1"
test "$(lines "$UPS_LOG")" -eq 3
run rollback backend > /dev/null 2>&1
test "$(head_of "$BACKEND_DIR")" = "$C1"

# 5) rollback на явную версию (коммит), ошибка на неизвестной
run rollback backend "$C2" > "$tmp/rollback3.log" 2>&1
test "$(head_of "$BACKEND_DIR")" = "$C2"
run_fail "$tmp/badref.log" rollback backend nosuchref
grep -q 'нет версии «nosuchref»' "$tmp/badref.log"

# 6) status показывает откат: отсоединённый HEAD и точку отката
run status backend > "$tmp/status.log" 2>&1
grep -q 'HEAD отсоединён' "$tmp/status.log"
grep -q 'точка отката:' "$tmp/status.log"

# --- admin: npm-приложение без compose --------------------------------------

git init -q -b main "$tmp/rem-admin"
printf '{"name":"privy-admin"}\n' > "$tmp/rem-admin/package.json"
git -C "$tmp/rem-admin" add -A
git_commit "$tmp/rem-admin" -m 'a1'
git clone -q "$tmp/rem-admin" "$tmp/apps/privy-admin"
printf '{"name":"privy-admin","v":2}\n' > "$tmp/rem-admin/package.json"
git_commit "$tmp/rem-admin" -a -m 'a2'
A1="$(git -C "$tmp/rem-admin" rev-parse HEAD~1)"
A2="$(git -C "$tmp/rem-admin" rev-parse HEAD)"
export ADMIN_DIR="$tmp/apps/privy-admin"

# 7) без точки отката rollback падает с понятной ошибкой
run_fail "$tmp/norollback.log" rollback admin
grep -q 'нет записанной предыдущей версии' "$tmp/norollback.log"

# 8) update и rollback админки идут через npm
run update admin > /dev/null 2>&1
test "$(head_of "$ADMIN_DIR")" = "$A2"
test "$(lines "$NPM_LOG")" -eq 2
run rollback admin > /dev/null 2>&1
test "$(head_of "$ADMIN_DIR")" = "$A1"
test "$(lines "$NPM_LOG")" -eq 4

# --- rollback cli: установленная копия и git-клон ---------------------------

# локальный «GitHub»: cli v1.0.0 → v2.0.0 → v3.0.0
git init -q -b main "$tmp/rem-cli"
sed 's/^PC_VERSION=.*/PC_VERSION=1.0.0/' "$repo/privy-cli" > "$tmp/rem-cli/privy-cli"
chmod 755 "$tmp/rem-cli/privy-cli" # иначе клон будет неисполняемым
git -C "$tmp/rem-cli" add -A
git_commit "$tmp/rem-cli" -m 'cli v1'
sed 's/^PC_VERSION=.*/PC_VERSION=2.0.0/' "$repo/privy-cli" > "$tmp/rem-cli/privy-cli"
git_commit "$tmp/rem-cli" -a -m 'cli v2'
CL1="$(git -C "$tmp/rem-cli" rev-parse HEAD)" # v2 — версия клона до update до v3

# 9) установленная копия: update сохраняет прежнюю версию, rollback меняет местами
mkdir -p "$tmp/sysbin"
sed 's/^PC_VERSION=.*/PC_VERSION=1.0.0/' "$repo/privy-cli" > "$tmp/sysbin/privy-cli"
chmod 755 "$tmp/sysbin/privy-cli"
CLI_REPO="$tmp/rem-cli" PATH="$tmp/bin:$PATH" \
  "$tmp/sysbin/privy-cli" update self > "$tmp/cli-update.log" 2>&1
grep -q 'обновлён: 1.0.0 → 2.0.0' "$tmp/cli-update.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/sysbin/privy-cli")" = "2.0.0"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/sysbin/.privy-cli.prev")" = "1.0.0"
test -x "$tmp/sysbin/.privy-cli.prev"
CLI_REPO="$tmp/rem-cli" PATH="$tmp/bin:$PATH" \
  "$tmp/sysbin/privy-cli" rollback self > "$tmp/cli-rollback.log" 2>&1
grep -q 'откат 2.0.0 → 1.0.0' "$tmp/cli-rollback.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/sysbin/privy-cli")" = "1.0.0"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/sysbin/.privy-cli.prev")" = "2.0.0"

# 10) update после отката снова ставит 2.0.0: upstream новее откаченной
CLI_REPO="$tmp/rem-cli" PATH="$tmp/bin:$PATH" \
  "$tmp/sysbin/privy-cli" update self > "$tmp/cli-update2.log" 2>&1
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/sysbin/privy-cli")" = "2.0.0"

# 11) без сохранённой предыдущей версии rollback cli падает с подсказкой
mkdir -p "$tmp/freshbin"
sed 's/^PC_VERSION=.*/PC_VERSION=1.0.0/' "$repo/privy-cli" > "$tmp/freshbin/privy-cli"
chmod 755 "$tmp/freshbin/privy-cli"
if CLI_REPO="$tmp/rem-cli" PATH="$tmp/bin:$PATH" \
    "$tmp/freshbin/privy-cli" rollback self > "$tmp/noprev.log" 2>&1; then
  echo 'ожидалась ошибка: rollback cli без .privy-cli.prev' >&2
  exit 1
fi
grep -q 'сохранённой предыдущей версии нет' "$tmp/noprev.log"

# 12) git-клон cli: update пишет точку отката, rollback чекаутит прошлый коммит
git clone -q "$tmp/rem-cli" "$tmp/cli-clone"
sed 's/^PC_VERSION=.*/PC_VERSION=3.0.0/' "$repo/privy-cli" > "$tmp/rem-cli/privy-cli"
git_commit "$tmp/rem-cli" -a -m 'cli v3'
CLI_REPO="$tmp/rem-cli" PATH="$tmp/bin:$PATH" \
  "$tmp/cli-clone/privy-cli" update self > "$tmp/clone-update.log" 2>&1
grep -q 'обновлён: 2.0.0 → 3.0.0' "$tmp/clone-update.log"
test "$(state_of "$tmp/cli-clone")" = "$CL1"
CLI_REPO="$tmp/rem-cli" PATH="$tmp/bin:$PATH" \
  "$tmp/cli-clone/privy-cli" rollback self > "$tmp/clone-rollback.log" 2>&1
grep -q 'откачен: 3.0.0 → 2.0.0' "$tmp/clone-rollback.log"
test "$(sed -n 's/^PC_VERSION=//p' "$tmp/cli-clone/privy-cli")" = "2.0.0"
test "$(head_of "$tmp/cli-clone")" = "$CL1"

echo 'rollback: приложение откатывается к точке отката и к явному коммиту, update после отката возвращается на ветку; cli откатывается и в клоне, и как установленная копия'
