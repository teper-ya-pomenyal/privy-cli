#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
test "$1" = clone
mkdir -p "$3"
GIT

cat > "$tmp/bin/npm" <<'NPM'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  ci) ;;
  'run build')
    mkdir -p dist/assets
    printf '<script src="/admin/assets/app.js"></script>\n' > dist/index.html ;;
  *) exit 1 ;;
esac
NPM

cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'compose version' | "ps -a --format {{.Names}}") ;;
  run\ *) printf '%s\n' "$*" > "$FAKE_ROOT/docker-run" ;;
  *) echo "unexpected docker command: $*" >&2; exit 1 ;;
esac
DOCKER
chmod +x "$tmp/bin/git" "$tmp/bin/npm" "$tmp/bin/docker"

FAKE_ROOT="$tmp" PATH="$tmp/bin:$PATH" ADMIN_DIR="$tmp/admin" \
  bash "$repo/privy-cli" install admin > "$tmp/install.log" 2>&1

conf="$tmp/admin/privy-admin.nginx.conf"
test -s "$conf"
grep -q 'location /admin/' "$conf"
grep -q 'alias /usr/share/nginx/html/' "$conf"
grep -q 'try_files .* /admin/index.html' "$conf"
grep -q 'proxy_pass http://host.docker.internal:8080' "$conf"
grep -q 'client_max_body_size 100m' "$conf"
grep -q -- '--add-host=host.docker.internal:host-gateway' "$tmp/docker-run"
grep -q -- '-p 8082:80' "$tmp/docker-run"
test ! -e "$tmp/admin/.privy-cli-install-incomplete"
echo 'admin install serves /admin assets and proxies API requests'
