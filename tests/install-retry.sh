#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = clone ]; then
  printf 'clone\n' >> "$FAKE_ROOT/clones"
  if [ "$3" = "$FAKE_ROOT/client" ]; then
    mkdir -p "$3/privy-stream"
    printf 'PRIVY_NODE_URL=https://placeholder.invalid\n' > "$3/privy-stream/.env.example"
  else
    mkdir -p "$3"
    printf 'POSTGRES_PASSWORD=example\nUSER_CACHE_PASSWORD=example\n' > "$3/.env.example"
  fi
  exit 0
fi
echo "unexpected git command: $*" >&2
exit 90
GIT

cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'compose version') exit 0 ;;
  'compose up -d --build')
    printf 'up\n' >> "$FAKE_ROOT/ups"
    if [ -f "$FAKE_ROOT/fail-up" ]; then
      rm "$FAKE_ROOT/fail-up"
      exit 1
    fi
    exit 0 ;;
  'image prune -f --filter until=48h') exit 0 ;;
  # buildx нет — legacy-билдер: как на старом docker без BuildKit
  'buildx version') exit 1 ;;
esac
echo "unexpected docker command: $*" >&2
exit 91
DOCKER
chmod +x "$tmp/bin/git" "$tmp/bin/docker"

export FAKE_ROOT="$tmp" PATH="$tmp/bin:$PATH" BACKEND_DIR="$tmp/backend" CLIENT_DIR="$tmp/client"
touch "$tmp/fail-up"
if bash "$repo/privy-cli" install backend > "$tmp/first.log" 2>&1; then
  echo 'first install unexpectedly succeeded' >&2
  exit 1
fi

test -f "$BACKEND_DIR/.env.example"
test -f "$BACKEND_DIR/.env"
test -f "$BACKEND_DIR/.privy-cli-install-incomplete"
initial_env_checksum="$(cksum < "$BACKEND_DIR/.env")"

bash "$repo/privy-cli" install backend > "$tmp/second.log" 2>&1
test "$(cksum < "$BACKEND_DIR/.env")" = "$initial_env_checksum"
test ! -e "$BACKEND_DIR/.privy-cli-install-incomplete"
test "$(wc -l < "$tmp/clones" | tr -d ' ')" = 1
test "$(wc -l < "$tmp/ups" | tr -d ' ')" = 2

bash "$repo/privy-cli" install backend > "$tmp/third.log" 2>&1
test "$(wc -l < "$tmp/ups" | tr -d ' ')" = 2

if bash "$repo/privy-cli" install client > "$tmp/client-first.log" 2>&1; then
  echo 'client install without node URL unexpectedly succeeded' >&2
  exit 1
fi
test -f "$CLIENT_DIR/privy-stream/.env"
test -f "$CLIENT_DIR/.privy-cli-install-incomplete"
if bash "$repo/privy-cli" install client > "$tmp/client-no-url.log" 2>&1; then
  echo 'client retry without node URL unexpectedly succeeded' >&2
  exit 1
fi
test "$(wc -l < "$tmp/ups" | tr -d ' ')" = 2
PRIVY_NODE_URL=https://node.example bash "$repo/privy-cli" install client > "$tmp/client-second.log" 2>&1
grep -q '^PRIVY_NODE_URL=https://node.example$' "$CLIENT_DIR/privy-stream/.env"
test ! -e "$CLIENT_DIR/.privy-cli-install-incomplete"
test "$(wc -l < "$tmp/clones" | tr -d ' ')" = 2
test "$(wc -l < "$tmp/ups" | tr -d ' ')" = 3
echo 'install retries preserve configuration and resume successfully'
