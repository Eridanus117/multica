#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  echo "Missing .env in $ROOT_DIR" >&2
  exit 1
fi

set -a
source .env
set +a

PORT="${PORT:-8080}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
CLAUDE_PATH="${MULTICA_CLAUDE_PATH:-}"

echo "==> Stopping local daemon..."
multica daemon stop >/dev/null 2>&1 || true

echo "==> Updating official Multica checkout..."
git pull --ff-only

echo "==> Rebuilding self-host services..."
docker compose -f docker-compose.selfhost.yml up -d --build

echo "==> Waiting for backend health..."
for _ in $(seq 1 60); do
  if curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1; then
  echo "Backend failed health check on port ${PORT}" >&2
  exit 1
fi

echo "==> Waiting for frontend..."
for _ in $(seq 1 60); do
  if curl -sfI "http://localhost:${FRONTEND_PORT}/login" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -sfI "http://localhost:${FRONTEND_PORT}/login" >/dev/null 2>&1; then
  echo "Frontend failed health check on port ${FRONTEND_PORT}" >&2
  exit 1
fi

echo "==> Starting daemon..."
if [ -n "$CLAUDE_PATH" ]; then
  MULTICA_CLAUDE_PATH="$CLAUDE_PATH" multica daemon start
else
  multica daemon start
fi

echo
echo "Upgrade complete."
echo "  Frontend: http://localhost:${FRONTEND_PORT}"
echo "  Backend:  http://localhost:${PORT}"
echo "  Daemon:   $(multica daemon status --output json | tr -d '\n')"
